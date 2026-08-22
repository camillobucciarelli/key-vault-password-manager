// spec-008 T205 — focused command use cases over the merge port.
//
// One class per port operation. `SyncMergeCoordinator` (Phase 5) depends on
// these and on nothing else.
//
// `LoadSyncMergeFieldDisplayUseCase` is deliberately NOT here: it is the only
// operation that returns plaintext, and it lives in its own library so that
// importing the command use cases cannot bring `MergeFieldDisplay` into scope.
import '../models/sync_merge_models.dart';
import '../repositories/sync_merge_repository.dart';

class StartSyncMergeReviewUseCase {
  const StartSyncMergeReviewUseCase(this._repository);

  final SyncMergeRepository _repository;

  Future<MergeReviewSummary> call(MergeDatabaseId databaseId) =>
      _repository.startReview(databaseId);
}

class UpdateSyncMergeDecisionUseCase {
  const UpdateSyncMergeDecisionUseCase(this._repository);

  final SyncMergeRepository _repository;

  Future<MergeReviewSummary> call({
    required MergeSessionId sessionId,
    required MergeDecisionId decisionId,
    required MergeChoice choice,
  }) => _repository.updateDecision(
    sessionId: sessionId,
    decisionId: decisionId,
    choice: choice,
  );
}

class CommitSyncMergeUseCase {
  const CommitSyncMergeUseCase(this._repository);

  final SyncMergeRepository _repository;

  Future<MergeCommitOutcome> call(MergeSessionId sessionId) =>
      _repository.commit(sessionId);
}

class CancelSyncMergeUseCase {
  const CancelSyncMergeUseCase(this._repository);

  final SyncMergeRepository _repository;

  Future<void> call(MergeSessionId sessionId) => _repository.cancel(sessionId);
}

class InvalidateSyncMergeUseCase {
  const InvalidateSyncMergeUseCase(this._repository);

  final SyncMergeRepository _repository;

  Future<void> call(MergeDatabaseId databaseId) =>
      _repository.invalidate(databaseId);
}

class RecoverPendingSyncMergeUploadUseCase {
  const RecoverPendingSyncMergeUploadUseCase(this._repository);

  final SyncMergeRepository _repository;

  Future<MergeRecoveryOutcome> call(MergeDatabaseId databaseId) =>
      _repository.recoverPending(databaseId);
}
