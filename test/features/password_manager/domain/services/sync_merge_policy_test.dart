// spec-008 T206 — domain policy tests. No data implementation exists and none
// is needed: every rule asserted here is decidable from the redacted models.
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/models/sync_merge_models.dart';
import 'package:password_manager/features/password_manager/domain/services/sync_merge_policy.dart';

void main() {
  group('visible defaults', () {
    test('every decision carries a pre-selected default', () {
      final summary = _summary([
        _fieldConflict(0, choice: MergeChoice.remote),
        _deletionConflict(1, MergePresence.localOnly),
      ]);
      for (final decision in summary.decisions) {
        expect(decision.isDefault, isTrue);
        expect(
          SyncMergePolicy.availableChoicesFor(decision),
          contains(decision.choice),
          reason: 'the default must be one of the offered choices',
        );
      }
    });

    test('an unattended deletion conflict defaults to keep, never delete', () {
      expect(
        () => _deletionConflict(
          0,
          MergePresence.localOnly,
          choice: MergeChoice.delete,
          isDefault: true,
        ),
        throwsArgumentError,
      );
      expect(
        _deletionConflict(0, MergePresence.localOnly).choice,
        MergeChoice.keep,
      );
    });

    test('answering a decision clears the default flag', () {
      final answered = _fieldConflict(0).withChoice(MergeChoice.remote);
      expect(answered.isDefault, isFalse);
      expect(answered.choice, MergeChoice.remote);
    });
  });

  group('deterministic both-sides notes', () {
    test('bothNotes is offered on a Notes field conflict', () {
      final notes = _fieldConflict(0, category: MergeFieldCategory.notes);
      expect(SyncMergePolicy.availableChoicesFor(notes), {
        MergeChoice.local,
        MergeChoice.remote,
        MergeChoice.bothNotes,
      });
      expect(
        notes.withChoice(MergeChoice.bothNotes).choice,
        MergeChoice.bothNotes,
      );
    });

    test('bothNotes is offered on no other category and no other kind', () {
      for (final category in MergeFieldCategory.values) {
        if (category == MergeFieldCategory.notes) continue;
        final decision = _fieldConflict(0, category: category);
        expect(
          SyncMergePolicy.availableChoicesFor(decision),
          isNot(contains(MergeChoice.bothNotes)),
          reason: '$category must not offer the both-sides union',
        );
        expect(
          () => decision.withChoice(MergeChoice.bothNotes),
          throwsArgumentError,
        );
      }
      final groupNotes = RedactedMergeDecision(
        decisionId: _id(9),
        ordinal: 0,
        kind: MergeDecisionKind.groupConflict,
        category: MergeFieldCategory.notes,
        presence: MergePresence.presentBoth,
        choice: MergeChoice.local,
        isDefault: true,
        timestampRelation: TimestampRelation.tie,
      );
      expect(
        SyncMergePolicy.availableChoicesFor(groupNotes),
        isNot(contains(MergeChoice.bothNotes)),
      );
    });

    test(
      'a tie or an unknown timestamp is still a resolved, visible default',
      () {
        for (final relation in [
          TimestampRelation.tie,
          TimestampRelation.bothUnknown,
          TimestampRelation.localKnownRemoteUnknown,
        ]) {
          final decision = _fieldConflict(0, relation: relation);
          // FR-3: the value-order tie-break fixes the default globally; the UI
          // marks the uncertainty through the relation, not by leaving the row
          // unanswered.
          expect(decision.choice, isNotNull);
          expect(decision.timestampRelation, relation);
        }
      },
    );
  });

  group('the shortcut decision set excludes one-sided rows', () {
    test('shortcuts answer decisions only; one-sided counts are untouched', () {
      final summary = _summary(
        [_fieldConflict(0), _fieldConflict(1)],
        localOnlyRecordCount: 7,
        remoteOnlyRecordCount: 5,
        oneSidedFieldCount: 11,
      );

      for (final shortcut in MergeShortcut.values) {
        final commands = SyncMergePolicy.commandsFor(summary, shortcut);
        expect(commands, hasLength(summary.decisions.length));
        expect(
          commands.map((c) => c.decisionId).toSet(),
          summary.decisions.map((d) => d.decisionId).toSet(),
          reason: 'a shortcut may address nothing but the decision list',
        );

        final applied = SyncMergePolicy.applyShortcut(summary, shortcut);
        expect(applied.localOnlyRecordCount, 7);
        expect(applied.remoteOnlyRecordCount, 5);
        expect(applied.oneSidedFieldCount, 11);
        expect(applied.decisions, hasLength(2));
      }
    });

    test(
      'a one-sided row without deletion evidence cannot exist as a decision',
      () {
        for (final presence in [
          MergePresence.localOnly,
          MergePresence.remoteOnly,
        ]) {
          for (final kind in [
            MergeDecisionKind.fieldConflict,
            MergeDecisionKind.groupConflict,
          ]) {
            expect(
              () => RedactedMergeDecision(
                decisionId: _id(1),
                ordinal: 0,
                kind: kind,
                category: MergeFieldCategory.customField,
                presence: presence,
                choice: MergeChoice.local,
                isDefault: true,
                timestampRelation: TimestampRelation.tie,
              ),
              throwsArgumentError,
              reason:
                  'FR-4: one-sided data without deletion evidence is an '
                  'automatic union, so it must be unrepresentable as a decision '
                  'and therefore unreachable by a shortcut',
            );
          }
        }
      },
    );
  });

  group('the missing side can never be selected', () {
    test('prefer local/remote never emit a choice naming an absent side', () {
      final summary = _summary([
        _deletionConflict(0, MergePresence.localOnly),
        _deletionConflict(1, MergePresence.remoteOnly),
        _fieldConflict(2),
      ]);

      for (final shortcut in MergeShortcut.values) {
        for (final command in SyncMergePolicy.commandsFor(summary, shortcut)) {
          final decision = summary.decisions.firstWhere(
            (d) => d.decisionId == command.decisionId,
          );
          if (decision.presence == MergePresence.localOnly) {
            expect(command.choice, isNot(MergeChoice.remote));
          }
          if (decision.presence == MergePresence.remoteOnly) {
            expect(command.choice, isNot(MergeChoice.local));
          }
          expect(
            SyncMergePolicy.availableChoicesFor(decision),
            contains(command.choice),
          );
        }
        // Applying re-runs every model invariant.
        expect(
          () => SyncMergePolicy.applyShortcut(summary, shortcut),
          returnsNormally,
        );
      }
    });

    test(
      'a shortcut maps the preferred side\'s own state to keep or delete',
      () {
        final summary = _summary([
          _deletionConflict(0, MergePresence.localOnly),
          _deletionConflict(1, MergePresence.remoteOnly),
        ]);

        final local = SyncMergePolicy.applyShortcut(
          summary,
          MergeShortcut.preferLocal,
        ).decisions;
        // Local holds the record -> keep it. Local deleted it -> delete.
        expect(local[0].choice, MergeChoice.keep);
        expect(local[1].choice, MergeChoice.delete);

        final remote = SyncMergePolicy.applyShortcut(
          summary,
          MergeShortcut.preferRemote,
        ).decisions;
        expect(remote[0].choice, MergeChoice.delete);
        expect(remote[1].choice, MergeChoice.keep);
      },
    );

    test('delete is never available without explicit deletion evidence', () {
      final valueConflict = _fieldConflict(0);
      expect(
        SyncMergePolicy.availableChoicesFor(valueConflict),
        isNot(contains(MergeChoice.delete)),
      );
      expect(
        () => valueConflict.withChoice(MergeChoice.delete),
        throwsArgumentError,
      );
      expect(
        () => valueConflict.withChoice(MergeChoice.keep),
        throwsArgumentError,
      );
    });

    test('a deletion conflict is never answered with a side', () {
      final deletion = _deletionConflict(0, MergePresence.localOnly);
      expect(SyncMergePolicy.availableChoicesFor(deletion), {
        MergeChoice.keep,
        MergeChoice.delete,
      });
      for (final choice in [
        MergeChoice.local,
        MergeChoice.remote,
        MergeChoice.bothNotes,
      ]) {
        expect(() => deletion.withChoice(choice), throwsArgumentError);
      }
    });
  });

  group('summary invariants', () {
    test('duplicate decision ids are rejected', () {
      expect(
        () => _summary([_fieldConflict(0), _fieldConflict(0)]),
        throwsArgumentError,
      );
    });

    test('negative counts are rejected', () {
      expect(() => _summary([], localOnlyRecordCount: -1), throwsArgumentError);
    });

    test('the decision list is unmodifiable', () {
      final summary = _summary([_fieldConflict(0)]);
      expect(
        () => summary.decisions.add(_fieldConflict(1)),
        throwsUnsupportedError,
      );
    });

    test('FR-11: above 200 conflicts the review is shortcuts-only', () {
      expect(
        _summary([
          for (var i = 0; i < 200; i++) _fieldConflict(i),
        ]).exceedsPerDecisionReviewLimit,
        isFalse,
      );
      expect(
        _summary([
          for (var i = 0; i < 201; i++) _fieldConflict(i),
        ]).exceedsPerDecisionReviewLimit,
        isTrue,
      );
    });
  });
}

MergeDecisionId _id(int seed) =>
    MergeDecisionId('md-${seed.toRadixString(16).padLeft(32, '0')}');

RedactedMergeDecision _fieldConflict(
  int ordinal, {
  MergeFieldCategory category = MergeFieldCategory.username,
  MergeChoice choice = MergeChoice.local,
  TimestampRelation relation = TimestampRelation.localNewer,
}) => RedactedMergeDecision(
  decisionId: _id(ordinal),
  ordinal: ordinal,
  kind: MergeDecisionKind.fieldConflict,
  category: category,
  presence: MergePresence.presentBoth,
  choice: choice,
  isDefault: true,
  timestampRelation: relation,
);

RedactedMergeDecision _deletionConflict(
  int ordinal,
  MergePresence presence, {
  MergeChoice choice = MergeChoice.keep,
  bool isDefault = true,
}) => RedactedMergeDecision(
  decisionId: _id(ordinal),
  ordinal: ordinal,
  kind: MergeDecisionKind.fieldDeletionConflict,
  category: MergeFieldCategory.customField,
  presence: presence,
  choice: choice,
  isDefault: isDefault,
  timestampRelation: TimestampRelation.localKnownRemoteUnknown,
);

MergeReviewSummary _summary(
  List<RedactedMergeDecision> decisions, {
  int localOnlyRecordCount = 0,
  int remoteOnlyRecordCount = 0,
  int oneSidedFieldCount = 0,
}) => MergeReviewSummary(
  sessionId: MergeSessionId('ms-${'0' * 32}'),
  databaseId: MergeDatabaseId('registry-db'),
  phase: MergeReviewPhase.reviewing,
  decisions: decisions,
  localOnlyRecordCount: localOnlyRecordCount,
  remoteOnlyRecordCount: remoteOnlyRecordCount,
  oneSidedFieldCount: oneSidedFieldCount,
);
