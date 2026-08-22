// spec-008 T204 — the merge domain port.
//
// Everything this port accepts and returns is opaque or redacted. The data
// implementation (Phase 3, `data/repositories/sync_merge_repository_impl.dart`)
// alone owns `KdbxFile`, decrypted values, attachment bytes, object UUID maps,
// credentials, canonical paths, checksums and the private session store. None
// of those has a representation in this file.
import '../models/merge_field_display.dart';
import '../models/sync_merge_models.dart';

abstract interface class SyncMergeRepository {
  /// Resolves credentials, validates lineage and UUID integrity, diffs both
  /// sides and returns the redacted review. Nothing is written.
  ///
  /// Throws [SyncMergeFailure] with [MergeFailureCode.wrongLineage] or
  /// [MergeFailureCode.unsupportedKdbxData] *before* any session exists, so a
  /// rejected pair never produces a session id, a backup or an upload.
  Future<MergeReviewSummary> startReview(MergeDatabaseId databaseId);

  /// Records one explicit user answer and returns the updated review.
  ///
  /// The choice is validated against the decision's presence and kind — a
  /// missing side can never be selected, and a delete always requires explicit
  /// deletion evidence.
  Future<MergeReviewSummary> updateDecision({
    required MergeSessionId sessionId,
    required MergeDecisionId decisionId,
    required MergeChoice choice,
  });

  /// Runs the FR-7 write-verify-converge cycle under the per-database mutex:
  /// revalidate, verified backup, atomic local replace, write, mandatory
  /// read-back. Returns [MergeNeedsReview] when a re-merge surfaces a conflict
  /// the user has never been shown.
  Future<MergeCommitOutcome> commit(MergeSessionId sessionId);

  /// Abandons a session before the atomic boundary and disposes its private
  /// store. After the boundary the data layer finishes durable bookkeeping
  /// instead of rolling back (FR-8).
  Future<void> cancel(MergeSessionId sessionId);

  /// Drops every session for this database — called on vault lock, database
  /// switch and credential clear, before the credentials go away.
  Future<void> invalidate(MergeDatabaseId databaseId);

  /// FR-10 restart recovery. Acquires the database mutex and compares the
  /// current local checksum against the persisted `localCommittedChecksum`
  /// before any remote call or vault mutation.
  Future<MergeRecoveryOutcome> recoverPending(MergeDatabaseId databaseId);

  /// The single transient plaintext read, for one visible decision.
  ///
  /// Called by the field widget only. The response is not `Equatable`, not
  /// serializable and must be disposed when the card unmounts or the vault
  /// locks.
  Future<MergeFieldDisplay> loadFieldDisplay({
    required MergeSessionId sessionId,
    required MergeDecisionId decisionId,
  });
}

/// The only error type the port itself raises. It carries a safe code and
/// nothing else: no raw exception, no path, no checksum, no token, no user
/// value.
///
/// It is **not** the only exception a caller can observe: the redacted models
/// throw `ArgumentError` when an illegal decision is constructed — see
/// `RedactedMergeDecision.withChoice`. That is a programming error on this side
/// of the port, not a merge outcome, and it deliberately stays an
/// `ArgumentError` so it is not caught and reported as a merge failure.
/// Tracked as F7; converting it into a total variant is a Phase 5 decision.
final class SyncMergeFailure implements Exception {
  const SyncMergeFailure(this.code, {this.localCommitCompleted = false});

  final MergeFailureCode code;

  /// True when the atomic local replace already ran; FR-8 forbids an automatic
  /// rollback past that point.
  final bool localCommitCompleted;

  @override
  String toString() =>
      'SyncMergeFailure(${code.name}, localCommitCompleted: '
      '$localCommitCompleted)';
}
