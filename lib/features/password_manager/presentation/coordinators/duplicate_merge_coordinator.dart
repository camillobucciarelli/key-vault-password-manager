import '../../data/services/vault_kdbx_service.dart';
import '../../domain/errors/passkey_errors.dart';
import '../../domain/repositories/database_file_repository.dart';
import 'dated_backup_path.dart';
import 'session_secret_holder.dart';

/// spec 023 T207 — how a duplicate merge ended. Never carries a secret.
enum DuplicateMergeOutcome {
  done,
  vaultLocked,

  /// The primary and a secondary hold different passkeys for the same relying
  /// party and account. Nothing was written (FR-011a).
  passkeyConflict,
  failed,
}

class DuplicateMergeResult {
  const DuplicateMergeResult(
    this.outcome, {
    this.backupPath,
    this.relyingPartyId,
  });

  final DuplicateMergeOutcome outcome;

  /// Where the pre-merge copy went. Set whenever the backup was written,
  /// including when the merge after it failed — a stray backup is
  /// recoverable, a missing one is not.
  final String? backupPath;

  /// The relying party the refused passkeys belong to, so the message can
  /// name the site. Only set for [DuplicateMergeOutcome.passkeyConflict].
  final String? relyingPartyId;

  @override
  String toString() =>
      'DuplicateMergeResult($outcome, backupPath: $backupPath, '
      'relyingPartyId: $relyingPartyId)';
}

/// spec 023 T207 — sequencing for a duplicate merge: the dated backup first,
/// then the merge (Constitution VII).
///
/// A merge moves the secondaries to the recycle bin, which is recoverable on
/// its own, but since spec 023 it can also move a passkey — the one copy of a
/// private key — from one entry to another. That makes the dated copy the only
/// way back from a merge that turns out to have been the wrong one, so it is
/// written before the vault is touched and a backup that cannot be written
/// stops the merge.
///
/// The confirmation is the caller's: this must stay callable from a test
/// without a UI.
class DuplicateMergeCoordinator {
  DuplicateMergeCoordinator({
    required this.vaultKdbxService,
    required this.sessionSecretHolder,
    required this.databaseFileRepository,
  });

  final VaultKdbxService vaultKdbxService;
  final SessionSecretHolder sessionSecretHolder;
  final DatabaseFileRepository databaseFileRepository;

  Future<DuplicateMergeResult> merge({
    required String databasePath,
    String? keyFilePath,
    required String primaryId,
    required List<String> secondaryIds,
  }) async {
    if (!sessionSecretHolder.hasSecret) {
      return const DuplicateMergeResult(DuplicateMergeOutcome.vaultLocked);
    }
    final backupPath = datedBackupPath(databasePath, suffix: 'pre-merge');
    try {
      await databaseFileRepository.copyFile(
        sourcePath: databasePath,
        targetPath: backupPath,
      );
    } catch (_) {
      return const DuplicateMergeResult(DuplicateMergeOutcome.failed);
    }
    try {
      await vaultKdbxService.mergeEntries(
        databasePath: databasePath,
        password: sessionSecretHolder.read(),
        keyFilePath: keyFilePath,
        primaryId: primaryId,
        secondaryIds: secondaryIds,
      );
      return DuplicateMergeResult(
        DuplicateMergeOutcome.done,
        backupPath: backupPath,
      );
    } on PasskeyMergeConflict catch (conflict) {
      // The service refused before writing anything, so the backup is a spare
      // copy rather than a restore point. It is still reported: a file that
      // appeared next to the vault should never be a surprise.
      return DuplicateMergeResult(
        DuplicateMergeOutcome.passkeyConflict,
        backupPath: backupPath,
        relyingPartyId: conflict.relyingPartyId,
      );
    } catch (_) {
      return DuplicateMergeResult(
        DuplicateMergeOutcome.failed,
        backupPath: backupPath,
      );
    }
  }
}
