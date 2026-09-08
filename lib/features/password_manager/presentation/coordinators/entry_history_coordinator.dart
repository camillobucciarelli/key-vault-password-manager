import '../../data/services/vault_kdbx_service.dart';
import '../../domain/repositories/database_file_repository.dart';
import 'dated_backup_path.dart';
import 'session_secret_holder.dart';

/// spec 017 — outcome of a history operation. Never carries a secret.
enum EntryHistoryOutcome { done, vaultLocked, failed }

class EntryHistoryRestoreResult {
  const EntryHistoryRestoreResult(this.outcome);

  final EntryHistoryOutcome outcome;

  @override
  String toString() => 'EntryHistoryRestoreResult($outcome)';
}

class EntryHistoryClearResult {
  const EntryHistoryClearResult(this.outcome, {this.backupPath});

  final EntryHistoryOutcome outcome;

  /// Where the pre-clear copy went. Set whenever the backup was written,
  /// including when the write after it failed — a stray backup is
  /// recoverable, a missing one is not.
  final String? backupPath;

  @override
  String toString() =>
      'EntryHistoryClearResult($outcome, backupPath: $backupPath)';
}

/// spec 017 T302/T402 — sequencing for the history operations that are more
/// than one step (`contracts/entry_history_coordinator.md`). Reading is a
/// single service call and stays in the bloc (Constitution VIII).
///
/// The confirmations are the caller's: this must stay callable from a test
/// without a UI.
class EntryHistoryCoordinator {
  EntryHistoryCoordinator({
    required this.vaultKdbxService,
    required this.sessionSecretHolder,
    required this.databaseFileRepository,
  });

  final VaultKdbxService vaultKdbxService;
  final SessionSecretHolder sessionSecretHolder;
  final DatabaseFileRepository databaseFileRepository;

  /// Refuses on a locked session — the vault locked between the confirmation
  /// and the act — and writes nothing. Otherwise restores and reports.
  Future<EntryHistoryRestoreResult> restore({
    required String databasePath,
    String? keyFilePath,
    required String entryId,
    required DateTime replacedAt,
  }) async {
    if (!sessionSecretHolder.hasSecret) {
      return const EntryHistoryRestoreResult(EntryHistoryOutcome.vaultLocked);
    }
    try {
      await vaultKdbxService.restoreEntryRevision(
        databasePath: databasePath,
        password: sessionSecretHolder.read(),
        keyFilePath: keyFilePath,
        entryId: entryId,
        replacedAt: replacedAt,
      );
      return const EntryHistoryRestoreResult(EntryHistoryOutcome.done);
    } catch (_) {
      return const EntryHistoryRestoreResult(EntryHistoryOutcome.failed);
    }
  }

  /// Refuses on a locked session, as above. Otherwise writes a dated backup
  /// of the `.kdbx` **before** touching it (FR-010, Constitution VII), then
  /// clears. A backup that cannot be written stops the clear: without the
  /// copy the destruction is not recoverable, which is the whole point.
  Future<EntryHistoryClearResult> clearHistory({
    required String databasePath,
    String? keyFilePath,
    required String entryId,
  }) async {
    if (!sessionSecretHolder.hasSecret) {
      return const EntryHistoryClearResult(EntryHistoryOutcome.vaultLocked);
    }
    final backupPath = datedBackupPath(
      databasePath,
      suffix: 'pre-clear-history',
    );
    try {
      await databaseFileRepository.copyFile(
        sourcePath: databasePath,
        targetPath: backupPath,
      );
    } catch (_) {
      return const EntryHistoryClearResult(EntryHistoryOutcome.failed);
    }
    try {
      await vaultKdbxService.clearEntryHistory(
        databasePath: databasePath,
        password: sessionSecretHolder.read(),
        keyFilePath: keyFilePath,
        entryId: entryId,
      );
      return EntryHistoryClearResult(
        EntryHistoryOutcome.done,
        backupPath: backupPath,
      );
    } catch (_) {
      return EntryHistoryClearResult(
        EntryHistoryOutcome.failed,
        backupPath: backupPath,
      );
    }
  }
}
