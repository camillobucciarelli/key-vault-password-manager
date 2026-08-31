// spec-008 T501 — the presentation-side sequencer for a per-field merge.
//
// This class owns exactly three things: the opaque session id of the review
// in progress, the redacted summary the domain port returned for it, and a
// generation counter that lets a lock or database switch discard late
// callbacks. It depends on the domain command use cases only — no data
// imports, no credential resolution, no plaintext, no paths, checksums,
// tokens or UUIDs. Everything those stand for stays behind the port.
import '../../domain/models/sync_merge_models.dart';
import '../../domain/repositories/sync_merge_repository.dart'
    show SyncMergeFailure;
import '../../domain/services/sync_merge_policy.dart';
import '../../domain/usecases/sync_merge_usecases.dart';

class SyncMergeCoordinator {
  SyncMergeCoordinator({
    required StartSyncMergeReviewUseCase startReview,
    required UpdateSyncMergeDecisionUseCase updateDecision,
    required CommitSyncMergeUseCase commit,
    required CancelSyncMergeUseCase cancel,
    required InvalidateSyncMergeUseCase invalidate,
    required RecoverPendingSyncMergeUploadUseCase recoverPending,
  }) : _startReview = startReview,
       _updateDecision = updateDecision,
       _commit = commit,
       _cancel = cancel,
       _invalidate = invalidate,
       _recoverPending = recoverPending;

  final StartSyncMergeReviewUseCase _startReview;
  final UpdateSyncMergeDecisionUseCase _updateDecision;
  final CommitSyncMergeUseCase _commit;
  final CancelSyncMergeUseCase _cancel;
  final InvalidateSyncMergeUseCase _invalidate;
  final RecoverPendingSyncMergeUploadUseCase _recoverPending;

  MergeReviewSummary? _summary;

  /// Bumped by [invalidate] and [startReview]: an awaited port call that
  /// returns after a bump belongs to a session that no longer exists and is
  /// dropped (T506 — a database switch invalidates late callbacks).
  int _generation = 0;

  /// The redacted summary of the review in progress, or null.
  MergeReviewSummary? get currentReview => _summary;

  Future<MergeReviewSummary> startReview(MergeDatabaseId databaseId) async {
    await cancel();
    final generation = ++_generation;
    final summary = await _startReview(databaseId);
    if (generation != _generation) {
      // Invalidated while the port was diffing: the data side already
      // dropped its private session on invalidate; nothing to keep here.
      throw const SyncMergeFailure(MergeFailureCode.sessionInvalidated);
    }
    _summary = summary;
    return summary;
  }

  Future<MergeReviewSummary> updateDecision({
    required MergeDecisionId decisionId,
    required MergeChoice choice,
  }) async {
    final current = _requireSession();
    final generation = _generation;
    final summary = await _updateDecision(
      sessionId: current.sessionId,
      decisionId: decisionId,
      choice: choice,
    );
    _accept(generation, summary);
    return summary;
  }

  /// FR-6: a shortcut is a sequence of ordinary decisions, computed by the
  /// domain policy and applied one by one so every step is a redacted
  /// command the port already understands.
  Future<MergeReviewSummary> applyShortcut(MergeShortcut shortcut) async {
    var current = _requireSession();
    for (final command in SyncMergePolicy.commandsFor(current, shortcut)) {
      current = await updateDecision(
        decisionId: command.decisionId,
        choice: command.choice,
      );
    }
    return current;
  }

  Future<MergeCommitOutcome> commit() async {
    final current = _requireSession();
    final generation = _generation;
    final outcome = await _commit(current.sessionId);
    if (generation != _generation) {
      throw const SyncMergeFailure(MergeFailureCode.sessionInvalidated);
    }
    // A re-review keeps the session alive with a fresh summary; every other
    // outcome is terminal for it.
    _summary = switch (outcome) {
      MergeNeedsReview(:final summary) => summary,
      _ => null,
    };
    return outcome;
  }

  Future<void> cancel() async {
    final current = _summary;
    _summary = null;
    if (current != null) await _cancel(current.sessionId);
  }

  /// T506 — called by the lock/switch path BEFORE credentials are cleared.
  Future<void> invalidate(MergeDatabaseId databaseId) async {
    _generation++;
    _summary = null;
    await _invalidate(databaseId);
  }

  /// T507 — runs before a normal sync so an interrupted upload is triaged
  /// first. Holds no session.
  Future<MergeRecoveryOutcome> recoverPending(MergeDatabaseId databaseId) =>
      _recoverPending(databaseId);

  MergeReviewSummary _requireSession() {
    final current = _summary;
    if (current == null) {
      throw const SyncMergeFailure(MergeFailureCode.sessionInvalidated);
    }
    return current;
  }

  void _accept(int generation, MergeReviewSummary summary) {
    if (generation != _generation) {
      throw const SyncMergeFailure(MergeFailureCode.sessionInvalidated);
    }
    _summary = summary;
  }
}
