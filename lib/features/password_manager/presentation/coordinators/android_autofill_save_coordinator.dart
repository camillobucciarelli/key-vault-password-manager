import 'package:equatable/equatable.dart';
import 'package:loggy/loggy.dart';

import '../../data/services/vault_kdbx_service.dart';
import '../../domain/models/apple_autofill_v2_models.dart';
import '../../domain/models/vault_entry.dart';
import '../../domain/repositories/autofill_ports.dart';
import '../../domain/services/apple_autofill_v2_payload_mapper.dart';
import 'session_secret_holder.dart';

/// Whether a captured credential becomes a new entry or updates an existing
/// one. Stated to the user before anything is written (FR-008).
enum AndroidAutofillSaveKind { create, update }

/// A capture waiting for the user's decision.
class AndroidAutofillPendingSave extends Equatable {
  const AndroidAutofillPendingSave({
    required this.capture,
    required this.kind,
    this.existingEntry,
  });

  final AndroidAutofillCapture capture;
  final AndroidAutofillSaveKind kind;

  /// The entry the capture updates. Always set when [kind] is
  /// [AndroidAutofillSaveKind.update].
  final VaultEntry? existingEntry;

  /// What the new entry is called, or what the updated one is already called.
  String get displayTitle {
    final existingTitle = existingEntry?.title.trim();
    if (existingTitle != null && existingTitle.isNotEmpty) {
      return existingTitle;
    }
    return capture.association ?? capture.username;
  }

  @override
  List<Object?> get props => [capture, kind, existingEntry];
}

/// What happened to a capture. The token is resolved on every one of these.
enum AndroidAutofillSaveStatus { created, updated, notSaved, failed }

class AndroidAutofillSaveResult extends Equatable {
  const AndroidAutofillSaveResult(this.status, {this.entryTitle});

  final AndroidAutofillSaveStatus status;
  final String? entryTitle;

  @override
  List<Object?> get props => [status, entryTitle];
}

/// Turns a credential submitted to another app into a vault entry.
///
/// Sequencing only: the write goes through [VaultKdbxService], so it inherits
/// the existing backup, safe-writer and `DatabasePathMutex` protections
/// (FR-009), and the previous password lands in the entry's history because
/// that is what the KDBX writer already does on every edit. The native token is
/// resolved on every path, success and failure alike, so a capture never
/// lingers in the service's memory.
class AndroidAutofillSaveCoordinator {
  AndroidAutofillSaveCoordinator({
    required this.client,
    required this.mapper,
    required this.vaultKdbxService,
    required this.sessionSecretHolder,
  });

  final AppleAutofillV2Client client;
  final AppleAutofillV2PayloadMapper mapper;
  final VaultKdbxService vaultKdbxService;
  final SessionSecretHolder sessionSecretHolder;

  /// The token of a capture the app was launched for, once claimed from the
  /// native side. Held here because the native side hands it over exactly once,
  /// and the vault may still be locked when that happens.
  String? _heldToken;

  /// Whether a capture has already been claimed, answered without waiting.
  ///
  /// Claiming happens once at startup, so anything built afterwards — the
  /// unlock prompt's wording included — can ask without a channel round-trip.
  bool get hasClaimedCapture => _heldToken != null;

  /// Whether a capture is waiting for a vault that is not open yet.
  ///
  /// Claims the token from the native side on the first call so the unlock
  /// screen can say why it is asking, and keeps it for [takePendingSave].
  Future<bool> hasPendingCapture() async {
    if (!client.isSupported) {
      return false;
    }
    if (_heldToken != null) {
      return true;
    }
    _heldToken = await _claimToken();
    return _heldToken != null;
  }

  /// The user walked away from the unlock screen. Drop the capture now instead
  /// of leaving the submitted password in the service's memory until it
  /// expires.
  Future<void> abandonPendingCapture() async {
    final token = _heldToken;
    _heldToken = null;
    if (token == null) {
      return;
    }
    await _resolve(token, AndroidAutofillCaptureOutcome.cancelled);
  }

  /// Picks up a capture the app was launched for, if there is one.
  ///
  /// Returns `null` when nothing is pending, when the capture is already gone
  /// (process death, expiry, a second read), or on any platform without save
  /// capture.
  Future<AndroidAutofillPendingSave?> takePendingSave({
    required List<VaultEntry> entries,
  }) async {
    if (!client.isSupported) {
      return null;
    }

    final token = _heldToken ?? await _claimToken();
    _heldToken = null;
    if (token == null) {
      return null;
    }

    final AndroidAutofillCapture? capture;
    try {
      capture = await client.readPendingCapture(token);
    } on UnsupportedError {
      return null;
    } catch (e, st) {
      logWarning('Android autofill capture read failed.', e, st);
      await _resolve(token, AndroidAutofillCaptureOutcome.failed);
      return null;
    }
    if (capture == null) {
      return null;
    }

    return decide(capture: capture, entries: entries);
  }

  /// New-vs-update: an entry the vault already publishes for this association,
  /// under this username, is the one being changed. Everything else is new.
  AndroidAutofillPendingSave decide({
    required AndroidAutofillCapture capture,
    required List<VaultEntry> entries,
  }) {
    final association = capture.association?.trim().toLowerCase();
    final username = capture.username.trim().toLowerCase();
    if (association == null || association.isEmpty) {
      return AndroidAutofillPendingSave(
        capture: capture,
        kind: AndroidAutofillSaveKind.create,
      );
    }

    for (final entry in entries) {
      if (entry.username.trim().toLowerCase() != username) {
        continue;
      }
      final credential = mapper.mapEntry(entry);
      if (credential == null) {
        continue;
      }
      final matches = credential.serviceIdentifiers.any(
        (identifier) => identifier.value.trim().toLowerCase() == association,
      );
      if (matches) {
        return AndroidAutofillPendingSave(
          capture: capture,
          kind: AndroidAutofillSaveKind.update,
          existingEntry: entry,
        );
      }
    }

    return AndroidAutofillPendingSave(
      capture: capture,
      kind: AndroidAutofillSaveKind.create,
    );
  }

  /// Writes the confirmed capture and resolves its token.
  Future<AndroidAutofillSaveResult> confirm({
    required AndroidAutofillPendingSave pending,
    required String databasePath,
    String? keyFilePath,
    required String groupId,
  }) async {
    final capture = pending.capture;
    if (!sessionSecretHolder.hasSecret) {
      // The vault locked between the prompt and the confirmation.
      await _resolve(capture.token, AndroidAutofillCaptureOutcome.cancelled);
      return const AndroidAutofillSaveResult(
        AndroidAutofillSaveStatus.notSaved,
      );
    }

    final password = sessionSecretHolder.read();
    try {
      final existing = pending.existingEntry;
      if (pending.kind == AndroidAutofillSaveKind.update && existing != null) {
        await vaultKdbxService.updateEntry(
          databasePath: databasePath,
          password: password,
          keyFilePath: keyFilePath,
          entryId: existing.id,
          title: existing.title,
          username: existing.username,
          entryPassword: capture.password,
          url: existing.url,
          notes: existing.notes,
          customFields: existing.customFields,
        );
        await _resolve(capture.token, AndroidAutofillCaptureOutcome.updated);
        return AndroidAutofillSaveResult(
          AndroidAutofillSaveStatus.updated,
          entryTitle: pending.displayTitle,
        );
      }

      await vaultKdbxService.createEntry(
        databasePath: databasePath,
        password: password,
        keyFilePath: keyFilePath,
        groupId: groupId,
        title: pending.displayTitle,
        username: capture.username,
        entryPassword: capture.password,
        url: _urlForAssociation(capture),
        notes: '',
      );
      await _resolve(capture.token, AndroidAutofillCaptureOutcome.saved);
      return AndroidAutofillSaveResult(
        AndroidAutofillSaveStatus.created,
        entryTitle: pending.displayTitle,
      );
    } catch (e, st) {
      logError('Android autofill capture write failed.', e, st);
      await _resolve(capture.token, AndroidAutofillCaptureOutcome.failed);
      return const AndroidAutofillSaveResult(AndroidAutofillSaveStatus.failed);
    }
  }

  /// The user said no. The native side remembers it so the same submission is
  /// not offered again (FR-011).
  Future<AndroidAutofillSaveResult> decline(
    AndroidAutofillPendingSave pending,
  ) async {
    await _resolve(
      pending.capture.token,
      AndroidAutofillCaptureOutcome.declined,
    );
    return const AndroidAutofillSaveResult(AndroidAutofillSaveStatus.notSaved);
  }

  /// The user dismissed the confirmation without answering, or the vault could
  /// not be reached. Nothing is remembered; the same submission may prompt
  /// again.
  Future<AndroidAutofillSaveResult> cancel(
    AndroidAutofillPendingSave pending,
  ) async {
    await _resolve(
      pending.capture.token,
      AndroidAutofillCaptureOutcome.cancelled,
    );
    return const AndroidAutofillSaveResult(AndroidAutofillSaveStatus.notSaved);
  }

  /// A browser capture carries the site it came from; an app capture has no
  /// URL to record, and its package stays out of the entry's `url` field.
  String _urlForAssociation(AndroidAutofillCapture capture) {
    final domain = capture.webDomain?.trim();
    if (domain == null || domain.isEmpty) {
      return '';
    }
    return domain.contains('://') ? domain : 'https://$domain';
  }

  /// The native side yields the token once; `null` means nothing is pending.
  Future<String?> _claimToken() async {
    final String? token;
    try {
      token = await client.takePendingCaptureToken();
    } on UnsupportedError {
      return null;
    } catch (e, st) {
      logWarning('Android autofill capture token read failed.', e, st);
      return null;
    }
    return token == null || token.trim().isEmpty ? null : token;
  }

  Future<void> _resolve(
    String token,
    AndroidAutofillCaptureOutcome outcome,
  ) async {
    try {
      await client.resolvePendingCapture(token: token, outcome: outcome);
    } on UnsupportedError {
      return;
    } catch (e, st) {
      logWarning('Android autofill capture resolve failed.', e, st);
    }
  }
}
