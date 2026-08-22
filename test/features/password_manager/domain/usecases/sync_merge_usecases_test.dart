// spec-008 T205/T206 — the domain contract compiles and behaves with NO data
// implementation. The only `SyncMergeRepository` in existence here is a fake
// declared in this file; `SyncMergeRepositoryImpl` is Phase 3 and must not
// exist yet.
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/models/merge_field_display.dart';
import 'package:password_manager/features/password_manager/domain/models/sync_merge_models.dart';
import 'package:password_manager/features/password_manager/domain/repositories/sync_merge_repository.dart';
import 'package:password_manager/features/password_manager/domain/usecases/load_sync_merge_field_display_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/sync_merge_usecases.dart';

void main() {
  late _FakeSyncMergeRepository repository;

  final databaseId = MergeDatabaseId('registry-db');
  final sessionId = MergeSessionId('ms-${'1' * 32}');
  final decisionId = MergeDecisionId('md-${'2' * 32}');

  setUp(() => repository = _FakeSyncMergeRepository());

  test(
    'start review forwards the database id and returns the summary',
    () async {
      final summary = await StartSyncMergeReviewUseCase(repository)(databaseId);

      expect(repository.calls, ['startReview']);
      expect(repository.startedWith, databaseId);
      expect(summary.sessionId, sessionId);
      expect(summary.phase, MergeReviewPhase.reviewing);
    },
  );

  test('update decision forwards the opaque ids and the choice', () async {
    await UpdateSyncMergeDecisionUseCase(repository)(
      sessionId: sessionId,
      decisionId: decisionId,
      choice: MergeChoice.remote,
    );

    expect(repository.calls, ['updateDecision']);
    expect(repository.updatedDecision, decisionId);
    expect(repository.updatedChoice, MergeChoice.remote);
  });

  test('commit returns a typed outcome', () async {
    repository.commitOutcome = const MergeApplied(
      entryCount: 3,
      backupCreated: true,
      uploadState: MergeUploadState.pendingRecovery,
    );

    final outcome = await CommitSyncMergeUseCase(repository)(sessionId);

    expect(repository.calls, ['commit']);
    expect(outcome, isA<MergeApplied>());
    expect(
      (outcome as MergeApplied).uploadState,
      MergeUploadState.pendingRecovery,
    );
  });

  test(
    'commit can return the session to review with the new conflicts',
    () async {
      repository.commitOutcome = MergeNeedsReview(
        summary: repository.summary,
        newConflictCount: 1,
        reviewReentryCount: 2,
      );

      final outcome = await CommitSyncMergeUseCase(repository)(sessionId);

      expect(outcome, isA<MergeNeedsReview>());
      expect((outcome as MergeNeedsReview).newConflictCount, 1);
      expect(outcome.reviewReentryCount, 2);
    },
  );

  test('a rejected commit exposes a safe code and the boundary flag', () async {
    repository.commitOutcome = const MergeRejected(
      MergeFailureCode.staleRecoveryLocal,
      localCommitCompleted: true,
    );

    final outcome =
        await CommitSyncMergeUseCase(repository)(sessionId) as MergeRejected;

    expect(outcome.code, MergeFailureCode.staleRecoveryLocal);
    expect(outcome.localCommitCompleted, isTrue);
  });

  test('cancel and invalidate are fire-and-forget commands', () async {
    await CancelSyncMergeUseCase(repository)(sessionId);
    await InvalidateSyncMergeUseCase(repository)(databaseId);

    expect(repository.calls, ['cancel', 'invalidate']);
  });

  test('recover pending returns a redacted disposition', () async {
    repository.recoveryOutcome = const MergeRecoveryOutcome(
      MergeRecoveryDisposition.staleRecoveryLocal,
    );

    final outcome = await RecoverPendingSyncMergeUploadUseCase(repository)(
      databaseId,
    );

    expect(repository.calls, ['recoverPending']);
    expect(outcome.disposition, MergeRecoveryDisposition.staleRecoveryLocal);
  });

  test(
    'the field display use case returns a transient, disposable response',
    () async {
      final display = await LoadSyncMergeFieldDisplayUseCase(repository)(
        sessionId: sessionId,
        decisionId: decisionId,
      );

      expect(repository.calls, ['loadFieldDisplay']);
      expect(display.local.value, 'local-secret');
      expect(display.remote.isPresent, isFalse);
      expect(display, isNot(isA<Comparable<Object>>()));

      display.dispose();
      expect(() => display.local.value, throwsStateError);
    },
  );

  test('the port surfaces failures as a safe code only', () {
    const failure = SyncMergeFailure(MergeFailureCode.wrongLineage);

    expect(failure.code, MergeFailureCode.wrongLineage);
    expect(failure.localCommitCompleted, isFalse);
    expect(failure.toString(), contains('wrongLineage'));
    expect(failure.toString(), isNot(contains('/')));
  });
}

class _FakeSyncMergeRepository implements SyncMergeRepository {
  final calls = <String>[];

  MergeDatabaseId? startedWith;
  MergeDecisionId? updatedDecision;
  MergeChoice? updatedChoice;

  MergeCommitOutcome commitOutcome = const MergeApplied(
    entryCount: 0,
    backupCreated: true,
    uploadState: MergeUploadState.uploaded,
  );
  MergeRecoveryOutcome recoveryOutcome = const MergeRecoveryOutcome(
    MergeRecoveryDisposition.none,
  );

  late final MergeReviewSummary summary = MergeReviewSummary(
    sessionId: MergeSessionId('ms-${'1' * 32}'),
    databaseId: MergeDatabaseId('registry-db'),
    phase: MergeReviewPhase.reviewing,
    decisions: [
      RedactedMergeDecision(
        decisionId: MergeDecisionId('md-${'2' * 32}'),
        ordinal: 0,
        kind: MergeDecisionKind.fieldConflict,
        category: MergeFieldCategory.password,
        presence: MergePresence.presentBoth,
        choice: MergeChoice.local,
        isDefault: true,
        timestampRelation: TimestampRelation.tie,
      ),
    ],
    localOnlyRecordCount: 1,
    remoteOnlyRecordCount: 2,
    oneSidedFieldCount: 3,
  );

  @override
  Future<MergeReviewSummary> startReview(MergeDatabaseId databaseId) async {
    calls.add('startReview');
    startedWith = databaseId;
    return summary;
  }

  @override
  Future<MergeReviewSummary> updateDecision({
    required MergeSessionId sessionId,
    required MergeDecisionId decisionId,
    required MergeChoice choice,
  }) async {
    calls.add('updateDecision');
    updatedDecision = decisionId;
    updatedChoice = choice;
    return summary;
  }

  @override
  Future<MergeCommitOutcome> commit(MergeSessionId sessionId) async {
    calls.add('commit');
    return commitOutcome;
  }

  @override
  Future<void> cancel(MergeSessionId sessionId) async => calls.add('cancel');

  @override
  Future<void> invalidate(MergeDatabaseId databaseId) async =>
      calls.add('invalidate');

  @override
  Future<MergeRecoveryOutcome> recoverPending(
    MergeDatabaseId databaseId,
  ) async {
    calls.add('recoverPending');
    return recoveryOutcome;
  }

  @override
  Future<MergeFieldDisplay> loadFieldDisplay({
    required MergeSessionId sessionId,
    required MergeDecisionId decisionId,
  }) async {
    calls.add('loadFieldDisplay');
    return MergeFieldDisplay(
      label: 'Custom field',
      local: MergeDisplaySide.present('local-secret'),
      remote: MergeDisplaySide.missing(),
      protected: true,
    );
  }
}
