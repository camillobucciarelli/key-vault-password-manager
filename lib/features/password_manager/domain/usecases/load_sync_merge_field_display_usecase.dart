// spec-008 T205/T203 — the one use case that returns plaintext.
//
// Isolated in its own library on purpose: the field widget imports this file,
// and nothing else in `presentation/` may. Importing the command use cases
// (`sync_merge_usecases.dart`) does not bring `MergeFieldDisplay` into scope,
// so a coordinator or a BLoC cannot hold the response even by accident.
import '../models/merge_field_display.dart';
import '../models/sync_merge_models.dart';
import '../repositories/sync_merge_repository.dart';

class LoadSyncMergeFieldDisplayUseCase {
  const LoadSyncMergeFieldDisplayUseCase(this._repository);

  final SyncMergeRepository _repository;

  /// The caller owns the returned response and must `dispose()` it when the
  /// card unmounts or the vault locks.
  Future<MergeFieldDisplay> call({
    required MergeSessionId sessionId,
    required MergeDecisionId decisionId,
  }) => _repository.loadFieldDisplay(
    sessionId: sessionId,
    decisionId: decisionId,
  );
}
