// spec-008 T206 — the domain policy the review UI and the coordinator share.
//
// Pure functions over redacted models. No I/O, no data types, no plaintext:
// every rule here is decidable from the redacted decision alone, which is what
// lets the shortcut and the choice affordances be tested with no data
// implementation at all.
import '../models/sync_merge_models.dart';

enum MergeShortcut { preferLocal, preferRemote }

/// One shortcut command: the decision to answer, and the answer.
typedef MergeShortcutCommand = ({
  MergeDecisionId decisionId,
  MergeChoice choice,
});

abstract final class SyncMergePolicy {
  /// The choices the UI may offer for one decision (FR-4/FR-5/FR-3).
  ///
  /// - a value conflict offers the two sides, plus the deterministic
  ///   both-sides segment union on Notes;
  /// - a deletion conflict offers keep/delete only — a delete is never inferred
  ///   from absence;
  /// - a side that is missing is never offered, on either kind.
  static Set<MergeChoice> availableChoicesFor(RedactedMergeDecision decision) {
    switch (decision.kind) {
      case MergeDecisionKind.fieldDeletionConflict:
      case MergeDecisionKind.recordDeletionConflict:
        return const {MergeChoice.keep, MergeChoice.delete};
      case MergeDecisionKind.fieldConflict:
      case MergeDecisionKind.groupConflict:
        return {
          if (decision.presence != MergePresence.remoteOnly) MergeChoice.local,
          if (decision.presence != MergePresence.localOnly) MergeChoice.remote,
          if (decision.kind == MergeDecisionKind.fieldConflict &&
              decision.category == MergeFieldCategory.notes)
            MergeChoice.bothNotes,
        };
    }
  }

  /// FR-6: the decision set a shortcut answers.
  ///
  /// It iterates [MergeReviewSummary.decisions] and nothing else. One-sided
  /// records and one-sided fields are counts in the summary, never decisions,
  /// so no shortcut can reach them and no shortcut can delete them.
  ///
  /// On a deletion conflict the shortcut maps the *preferred side's own state*
  /// to an explicit keep or delete: preferring a side that holds the record
  /// keeps it, preferring the side that deleted it deletes it. Absence is never
  /// read as a delete, and `null` is never chosen.
  static List<MergeShortcutCommand> commandsFor(
    MergeReviewSummary summary,
    MergeShortcut shortcut,
  ) {
    return [
      for (final decision in summary.decisions)
        (
          decisionId: decision.decisionId,
          choice: _choiceFor(decision, shortcut),
        ),
    ];
  }

  static MergeChoice _choiceFor(
    RedactedMergeDecision decision,
    MergeShortcut shortcut,
  ) {
    final prefersLocal = shortcut == MergeShortcut.preferLocal;
    switch (decision.kind) {
      case MergeDecisionKind.fieldDeletionConflict:
      case MergeDecisionKind.recordDeletionConflict:
        // The preferred side is the one whose deletion evidence, or whose live
        // value, the user is electing to follow.
        final preferredSideIsPresent = switch (decision.presence) {
          MergePresence.localOnly => prefersLocal,
          MergePresence.remoteOnly => !prefersLocal,
          // Both sides live with deletion evidence elsewhere in the pair:
          // preserving is the only non-destructive reading (FR-5 default Keep).
          MergePresence.presentBoth => true,
        };
        return preferredSideIsPresent ? MergeChoice.keep : MergeChoice.delete;
      case MergeDecisionKind.fieldConflict:
      case MergeDecisionKind.groupConflict:
        return prefersLocal ? MergeChoice.local : MergeChoice.remote;
    }
  }

  /// Applies a shortcut locally so the review can be previewed before the
  /// commands reach the port. Every answer goes through
  /// [RedactedMergeDecision.withChoice], so an illegal shortcut answer throws
  /// here rather than silently reaching the data layer.
  static MergeReviewSummary applyShortcut(
    MergeReviewSummary summary,
    MergeShortcut shortcut,
  ) {
    final commands = {
      for (final command in commandsFor(summary, shortcut))
        command.decisionId: command.choice,
    };
    return MergeReviewSummary(
      sessionId: summary.sessionId,
      databaseId: summary.databaseId,
      phase: summary.phase,
      decisions: [
        for (final decision in summary.decisions)
          decision.withChoice(commands[decision.decisionId]!),
      ],
      localOnlyRecordCount: summary.localOnlyRecordCount,
      remoteOnlyRecordCount: summary.remoteOnlyRecordCount,
      oneSidedFieldCount: summary.oneSidedFieldCount,
    );
  }
}
