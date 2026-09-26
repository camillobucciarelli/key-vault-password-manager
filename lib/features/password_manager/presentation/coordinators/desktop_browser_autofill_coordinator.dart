import 'dart:convert';
import 'dart:typed_data';

import 'package:loggy/loggy.dart';

import '../../data/services/desktop_browser_autofill_cache.dart';
import '../../data/services/desktop_browser_autofill_reveal_bridge_service.dart';
import '../../data/services/desktop_browser_pending_generation_service.dart';
import '../../data/services/desktop_passkey_approval_service.dart';
import '../../domain/models/apple_autofill_v2_models.dart';
import '../../domain/models/vault_entry.dart';
import 'apple_autofill_v2_coordinator.dart';
import 'passkey_coordinator.dart';

class DesktopBrowserAutofillCoordinator
    implements AppleAutofillV2CoordinatorContract {
  DesktopBrowserAutofillCoordinator({
    required this.store,
    required this.mapper,
    required this.revealBridge,
    this.pendingGeneration,
    this.passkeyCoordinator,
    this.passkeyApprovals,
    this.currentKeyFilePath,
  });

  final DesktopBrowserAutofillCacheStore store;
  final DesktopBrowserAutofillMetadataMapper mapper;
  final DesktopBrowserAutofillRevealBridgeService revealBridge;

  /// 009 / B004 — in-memory pending generated secrets. Cleared whenever the
  /// reveal-bridge session ends or restarts: lock, database switch, and vault
  /// close all route through [clearCredentials]; a republish invalidates the
  /// previous session in [publishVault].
  final DesktopBrowserPendingGenerationService? pendingGeneration;

  /// spec 023 US3 — writes a created passkey to the open vault. Null in a host
  /// that cannot write one, and then the bridge never advertises
  /// `passkeyCreateV1`.
  final PasskeyCoordinator? passkeyCoordinator;

  /// spec 023 — where the bridge's confirmations are answered.
  final DesktopPasskeyApprovalService? passkeyApprovals;

  /// spec 014 FR-8: the active database's key-file path, read from its
  /// security profile at write time — the same source `VaultBloc` reads.
  ///
  /// Resolved per write rather than captured at publish: the publish contract
  /// carries only the path and the entries, and a key file that is added or
  /// changed mid-session would make a captured copy wrong. Without it a
  /// key-file-protected vault cannot be opened, so the write fails after the
  /// user has already confirmed.
  final Future<String?> Function()? currentKeyFilePath;

  @override
  Future<void> publishVault({
    required String databasePath,
    required List<VaultEntry> entries,
  }) async {
    pendingGeneration?.clearAll();
    if (store.directory == null) {
      return;
    }
    var metadataPublished = false;
    try {
      await store.writeMetadataCache(
        mapper.mapVault(databasePath: databasePath, entries: entries),
      );
      metadataPublished = true;
      // spec 023: the bridge's passkey hooks are bound per session, because
      // both need the path of the vault that is open right now. Rebinding on
      // every publish is what keeps a write from landing in the vault the user
      // just switched away from.
      _bindPasskeyHooks(databasePath);
      await revealBridge.start(databasePath: databasePath, entries: entries);
    } catch (e, st) {
      await _cleanupAfterPublishFailure(metadataPublished: metadataPublished);
      logWarning('Desktop browser Autofill cache publish failed.', e, st);
    }
  }

  Future<void> _cleanupAfterPublishFailure({
    required bool metadataPublished,
  }) async {
    try {
      pendingGeneration?.clearAll();
      _unbindPasskeyHooks();
      await revealBridge.stop();
      if (!metadataPublished) {
        await store.clearCredentials();
      }
    } catch (e, st) {
      logWarning('Desktop browser Autofill cache cleanup failed.', e, st);
    }
  }

  /// spec 023 — the two callbacks `/passkey-assert` and `/passkey-create` need.
  ///
  /// Both are cleared by [_unbindPasskeyHooks] on teardown, so a bridge that
  /// outlived its vault answers nothing rather than writing to a path that is
  /// no longer open.
  void _bindPasskeyHooks(String databasePath) {
    final approvals = passkeyApprovals;
    final coordinator = passkeyCoordinator;
    revealBridge.confirmPasskeyAssertion = approvals?.request;
    if (approvals == null || coordinator == null) {
      revealBridge.confirmPasskeyCreation = null;
      revealBridge.writePasskey = null;
      return;
    }
    revealBridge.confirmPasskeyCreation = approvals.requestCreation;
    revealBridge.writePasskey =
        ({
          required String entryId,
          required String relyingPartyId,
          required String username,
          required Uint8List? userHandle,
          required bool replaceExisting,
        }) async {
          final result = await coordinator.createPasskey(
            databasePath: databasePath,
            keyFilePath: await currentKeyFilePath?.call(),
            entryId: entryId,
            relyingPartyId: relyingPartyId,
            username: username,
            userHandle: userHandle,
            replaceExisting: replaceExisting,
          );
          final created = result.created;
          if (created == null) {
            return PasskeyCreationOutcome(
              reason: switch (result.outcome) {
                PasskeyOutcome.vaultLocked => 'vault_locked',
                PasskeyOutcome.alreadyExists => 'already_exists',
                PasskeyOutcome.notFound => 'no_credential',
                PasskeyOutcome.failed || PasskeyOutcome.done => 'write_failed',
              },
            );
          }
          // The vault on disk now holds a passkey this session's caches do
          // not. Until they are rebuilt, `_findPasskey` cannot see the new
          // credential and the bridge may not even advertise
          // `passkeyAssertV1`, so signing in right after registering would
          // fall through to the browser. The app window republishes on the
          // reload this asks for.
          approvals.notePasskeyWritten();
          return PasskeyCreationOutcome(
            reason: null,
            credentialId: _base64UrlUnpadded(created.passkey.credentialId),
            attestationObject: _base64UrlUnpadded(created.attestationObject),
            publicKeyCose: _base64UrlUnpadded(created.publicKeyCose),
          );
        };
  }

  void _unbindPasskeyHooks() {
    revealBridge.confirmPasskeyAssertion = null;
    revealBridge.confirmPasskeyCreation = null;
    revealBridge.writePasskey = null;
    passkeyApprovals?.declineAll();
  }

  static String _base64UrlUnpadded(Uint8List bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  @override
  Future<void> clearCredentials({String? databasePath}) async {
    pendingGeneration?.clearAll();
    _unbindPasskeyHooks();
    try {
      await revealBridge.stop();
      if (store.directory == null) {
        return;
      }
      await store.clearCredentials();
    } catch (e, st) {
      logWarning('Desktop browser Autofill cache clear failed.', e, st);
    }
  }

  /// 009 / B005 — hands a pending generated secret to the app's normal
  /// new-entry/save flow, exactly once. The app owns the vault mutation;
  /// the page/extension never reach this path and cannot auto-save.
  /// Slice B1/B2 (native `generatePendingEntry` + Generate UI) call this.
  PendingGeneratedNewEntryDraft? consumePendingGenerationForNewEntry({
    required String id,
    required String origin,
  }) {
    return pendingGeneration?.consume(id, origin: origin);
  }

  @override
  Future<List<AppleAutofillV2PendingAssociation>> readPendingAssociations({
    String? databasePath,
  }) async {
    final databaseId = databasePath == null || databasePath.trim().isEmpty
        ? null
        : DesktopBrowserAutofillMetadataMapper.databaseIdForPath(databasePath);
    if (databaseId == null) {
      return const [];
    }
    if (store.directory == null) {
      return const [];
    }

    try {
      final pending = await store.readPendingAssociations();
      return pending
          .where((association) => association.databaseId == databaseId)
          .map(
            (association) => AppleAutofillV2PendingAssociation(
              id: association.id,
              databaseId: association.databaseId,
              entryId: association.entryId,
              serviceIdentifierType: association.serviceIdentifierType,
              serviceIdentifierValue: association.serviceIdentifierValue,
              displayService: association.displayService,
              createdAtEpochMs: association.createdAtEpochMs,
              platform: association.platform,
            ),
          )
          .toList(growable: false);
    } catch (e, st) {
      logWarning('Desktop browser Autofill pending read failed.', e, st);
      return const [];
    }
  }

  @override
  Future<void> clearPendingAssociations({List<String>? ids}) async {
    if (store.directory == null) {
      return;
    }
    try {
      await store.clearPendingAssociations(ids: ids);
    } catch (e, st) {
      logWarning('Desktop browser Autofill pending clear failed.', e, st);
    }
  }
}

class CompositeAutofillV2Coordinator
    implements AppleAutofillV2CoordinatorContract {
  const CompositeAutofillV2Coordinator(this.coordinators);

  final List<AppleAutofillV2CoordinatorContract> coordinators;

  @override
  Future<void> publishVault({
    required String databasePath,
    required List<VaultEntry> entries,
  }) async {
    for (final coordinator in coordinators) {
      await coordinator.publishVault(
        databasePath: databasePath,
        entries: entries,
      );
    }
  }

  @override
  Future<void> clearCredentials({String? databasePath}) async {
    for (final coordinator in coordinators) {
      await coordinator.clearCredentials(databasePath: databasePath);
    }
  }

  @override
  Future<List<AppleAutofillV2PendingAssociation>> readPendingAssociations({
    String? databasePath,
  }) async {
    final result = <AppleAutofillV2PendingAssociation>[];
    final seen = <String>{};
    for (final coordinator in coordinators) {
      final pending = await coordinator.readPendingAssociations(
        databasePath: databasePath,
      );
      for (final association in pending) {
        if (seen.add(association.id)) {
          result.add(association);
        }
      }
    }
    result.sort((a, b) => a.createdAtEpochMs.compareTo(b.createdAtEpochMs));
    return result;
  }

  @override
  Future<void> clearPendingAssociations({List<String>? ids}) async {
    for (final coordinator in coordinators) {
      await coordinator.clearPendingAssociations(ids: ids);
    }
  }
}
