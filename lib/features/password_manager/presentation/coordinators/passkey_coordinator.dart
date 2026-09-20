import 'dart:typed_data';

import '../../data/services/vault_kdbx_service.dart';
import '../../domain/errors/passkey_errors.dart';
import '../../domain/repositories/database_file_repository.dart';
import 'dated_backup_path.dart';
import 'session_secret_holder.dart';

/// spec 023 — outcome of a passkey operation. Never carries a secret.
enum PasskeyOutcome { done, vaultLocked, notFound, failed }

class PasskeyDeleteResult {
  const PasskeyDeleteResult(this.outcome, {this.backupPath});

  final PasskeyOutcome outcome;

  /// Where the pre-delete copy went. Set whenever the backup was written,
  /// including when the delete after it failed — a stray backup is
  /// recoverable, a deleted private key is not.
  final String? backupPath;

  @override
  String toString() => 'PasskeyDeleteResult($outcome, backupPath: $backupPath)';
}

/// spec 023 T204 — sequencing for deleting a passkey (FR-010).
///
/// Mirrors `EntryHistoryCoordinator.clearHistory`: refuse on a locked
/// session, write the dated copy first, then the destructive call. The
/// confirmation is the caller's, so this stays callable from a test with no
/// UI (Constitution VIII).
class PasskeyCoordinator {
  PasskeyCoordinator({
    required this.vaultKdbxService,
    required this.sessionSecretHolder,
    required this.databaseFileRepository,
  });

  final VaultKdbxService vaultKdbxService;
  final SessionSecretHolder sessionSecretHolder;
  final DatabaseFileRepository databaseFileRepository;

  /// Named `deletePasskey`, not `delete`: spec 008 T102's architecture guard
  /// greps the presentation layer for a bare delete call on a receiver, to
  /// catch a `dart:io` mutation escaping the `DatabaseFileRepository` port.
  /// A one-word name here would read as exactly that — to the guard and to a
  /// reviewer.
  ///
  /// A backup that cannot be written stops the delete: a passkey has exactly
  /// one copy of its private key, and without the copy the destruction is
  /// unrecoverable — which is the whole point of Constitution VII here.
  Future<PasskeyDeleteResult> deletePasskey({
    required String databasePath,
    String? keyFilePath,
    required String entryId,
    required String relyingPartyId,
    required Uint8List credentialId,
  }) async {
    if (!sessionSecretHolder.hasSecret) {
      return const PasskeyDeleteResult(PasskeyOutcome.vaultLocked);
    }
    final backupPath = datedBackupPath(
      databasePath,
      suffix: 'pre-delete-passkey',
    );
    try {
      await databaseFileRepository.copyFile(
        sourcePath: databasePath,
        targetPath: backupPath,
      );
    } catch (_) {
      return const PasskeyDeleteResult(PasskeyOutcome.failed);
    }
    try {
      await vaultKdbxService.deletePasskey(
        databasePath: databasePath,
        password: sessionSecretHolder.read(),
        keyFilePath: keyFilePath,
        entryId: entryId,
        relyingPartyId: relyingPartyId,
        credentialId: credentialId,
      );
      return PasskeyDeleteResult(PasskeyOutcome.done, backupPath: backupPath);
    } on PasskeyNotFound {
      // The vault changed under the open record — synced, merged or edited
      // elsewhere. Nothing was written, but the backup stays: it is the only
      // copy of the file as the user last saw it.
      return PasskeyDeleteResult(
        PasskeyOutcome.notFound,
        backupPath: backupPath,
      );
    } catch (_) {
      return PasskeyDeleteResult(PasskeyOutcome.failed, backupPath: backupPath);
    }
  }
}
