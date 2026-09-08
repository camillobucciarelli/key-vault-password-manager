import '../../data/services/vault_kdbx_service.dart';
import 'session_secret_holder.dart';

/// spec 017 — outcome of a history operation. Never carries a secret.
enum EntryHistoryOutcome { done, vaultLocked, failed }

class EntryHistoryRestoreResult {
  const EntryHistoryRestoreResult(this.outcome);

  final EntryHistoryOutcome outcome;

  @override
  String toString() => 'EntryHistoryRestoreResult($outcome)';
}

/// spec 017 T302 — sequencing for the history operations that are more than
/// one step (`contracts/entry_history_coordinator.md`). Reading is a single
/// service call and stays in the bloc (Constitution VIII).
///
/// The confirmation is the caller's: this must stay callable from a test
/// without a UI.
class EntryHistoryCoordinator {
  EntryHistoryCoordinator({
    required this.vaultKdbxService,
    required this.sessionSecretHolder,
  });

  final VaultKdbxService vaultKdbxService;
  final SessionSecretHolder sessionSecretHolder;

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
}
