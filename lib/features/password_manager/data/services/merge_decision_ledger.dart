// spec-008 T401b — the session-lived sticky decision ledger.
//
// FR-7 "Explicit user decisions are sticky across a re-merge": a decision the
// user made once must not be silently reversed by a later automatic re-merge
// round, and it must not be REPLAYED onto a pair of candidates it was never
// taken over — that reduces to "take whichever side is second", which is
// defect C4's class of error relocated into the ledger branch. See
// `spec.md` FR-7 §"Explicit user decisions are sticky across a re-merge".
//
// **Session-lived only, deliberately.** No persistence beyond one commit
// session — extending it is exactly what reopens the invariant below, and
// spec.md is explicit that any such proposal must re-establish it first (it
// names `011-master-password-session-scope` as the live example). Nothing
// here touches disk.
//
// **This file delivers a primitive, not the FR-7 cycle.** Nothing here is
// wired into a re-merge: the cycle itself — read/merge/write/verify, the
// divergence branch, the review re-entry cap — is T401's job, still open.
// What this file owes T401 is the ledger's own invariants, independently
// testable with no `KdbxFile`, no filesystem, no mutex:
//
//   * a replayed local/remote decision must still name one of the two
//     CURRENT candidates, or it is reopened rather than guessed;
//   * "no entry" (never shown) and "entry names neither current candidate"
//     (stale — spec.md records this as unreachable today, defensive only)
//     stay distinguishable, because a future caller counts them differently;
//   * an operation (`bothNotes`/`keep`/`delete`) is not a side selection and
//     always replays verbatim — FR-7's invariant text is scoped to a
//     `local`/`remote` answer, and only that answer needs the check above.
//
// **Wiring contract for the future caller (T401).** Confirming a review must
// call [MergeDecisionLedger.recordField] /
// [MergeDecisionLedger.recordCredentialBlock] /
// [MergeDecisionLedger.recordRecord] for EVERY decision presented in that
// pass, including ones left at their automatic default — an absent entry
// means "never shown", and only that. A shortcut answers the same displayed
// set and must be recorded the same way.
import '../../domain/models/sync_merge_models.dart';
import 'kdbx_merge_adapter.dart';

/// The result of replaying one ledger entry against the CURRENT candidates.
///
/// Kept as three distinguishable states — never collapsed to a nullable
/// [MergeChoice] — because a future caller (T401) counts them differently:
/// [MergeLedgerNeverShown] is a genuinely new conflict, [MergeLedgerStale] is
/// the defensive branch spec.md records as unreachable today but requires
/// the ledger to still handle without guessing.
sealed class MergeLedgerReplay {
  const MergeLedgerReplay();
}

/// No ledger entry exists for this key. Never shown to the user.
final class MergeLedgerNeverShown extends MergeLedgerReplay {
  const MergeLedgerNeverShown();
}

/// An entry exists and is safe to replay verbatim: either it is an operation
/// ([MergeChoice.bothNotes]/[MergeChoice.keep]/[MergeChoice.delete]), which
/// is well-defined regardless of the current candidates, or it is a
/// local/remote selection whose recorded value still equals one of the two
/// current candidates.
final class MergeLedgerReplayed extends MergeLedgerReplay {
  const MergeLedgerReplayed(this.choice);
  final MergeChoice choice;
}

/// An entry exists, is a local/remote selection, and names NEITHER current
/// candidate. spec.md: resolving this automatically reduces to "take
/// whichever side is second" — silent, perspective-dependent data loss — so
/// the caller must reopen review instead, carrying both current candidates.
final class MergeLedgerStale extends MergeLedgerReplay {
  const MergeLedgerStale();
}

/// One recorded decision. [decidedValue] is populated only for a
/// local/remote [choice] — the snapshot FR-7's replay invariant checks
/// against, not the choice tag itself, since "local"/"remote" is meaningful
/// only against the pair it was decided over.
class MergeLedgerEntry {
  const MergeLedgerEntry(this.choice, {this.decidedValue});
  final MergeChoice choice;
  final Object? decidedValue;
}

/// Session-lived record of explicit user decisions.
///
/// Keyed the same way [KdbxMergeResolution] is: a field by [KdbxFieldRef], a
/// record deletion by object UUID, and an FR-3a credential block by entry
/// UUID ALONE — never by whichever field happens to be the block's current
/// anchor, so a block decision survives a re-merge that moves the anchor
/// from one member to another (spec.md T401c: "coordinated with T401b, so a
/// re-merge re-applies one decision and never re-splits it").
class MergeDecisionLedger {
  final Map<KdbxFieldRef, MergeLedgerEntry> _fields = {};
  final Map<String, MergeLedgerEntry> _credentialBlocks = {};
  final Map<String, MergeLedgerEntry> _records = {};

  /// Records (or overwrites) the decision for one field conflict.
  /// [decidedValue] must be supplied for [MergeChoice.local]/[.remote] — the
  /// winning side's [KdbxFieldPresent] AT DECISION TIME — and is ignored for
  /// [MergeChoice.bothNotes], which is an operation, not a side.
  void recordField(
    KdbxFieldRef ref,
    MergeChoice choice, {
    KdbxFieldPresent? decidedValue,
  }) {
    _fields[ref] = MergeLedgerEntry(choice, decidedValue: decidedValue);
  }

  /// Records the decision for one FR-3a credential block. [decidedValue] is
  /// the winning side's per-member snapshot, keyed by canonical field key —
  /// EVERY shared member must still match for the block to replay as one
  /// unit; a single stale member reopens the whole block, never a subset,
  /// which is FR-3a's own atomicity applied to the ledger.
  void recordCredentialBlock(
    String entryUuid,
    MergeChoice choice, {
    Map<String, KdbxFieldPresent>? decidedValue,
  }) {
    _credentialBlocks[entryUuid] = MergeLedgerEntry(
      choice,
      decidedValue: decidedValue,
    );
  }

  /// Records the decision for one record-level deletion conflict. Always
  /// keep/delete — an operation, so no candidate snapshot is needed.
  void recordRecord(String objectUuid, MergeChoice choice) {
    _records[objectUuid] = MergeLedgerEntry(choice);
  }

  /// Replays a field decision against the CURRENT candidates. `null` for a
  /// side means that side is absent on this round.
  MergeLedgerReplay replayField(
    KdbxFieldRef ref, {
    KdbxFieldPresent? currentLocal,
    KdbxFieldPresent? currentRemote,
  }) {
    final entry = _fields[ref];
    if (entry == null) return const MergeLedgerNeverShown();
    return _replayValue(
      entry,
      matchesLocal:
          currentLocal != null &&
          (entry.decidedValue as KdbxFieldPresent?)?.sameAs(currentLocal) ==
              true,
      matchesRemote:
          currentRemote != null &&
          (entry.decidedValue as KdbxFieldPresent?)?.sameAs(currentRemote) ==
              true,
    );
  }

  /// Replays a credential-block decision. The recorded side must still match
  /// EVERY shared member the block currently has — a single member whose
  /// value moved is enough to reopen the whole block, per FR-3a's own
  /// atomicity: a decision naming half the old block and half something new
  /// is exactly the chimera FR-3a exists to prevent.
  MergeLedgerReplay replayCredentialBlock(
    String entryUuid, {
    required Map<String, KdbxFieldPresent> currentLocal,
    required Map<String, KdbxFieldPresent> currentRemote,
  }) {
    final entry = _credentialBlocks[entryUuid];
    if (entry == null) return const MergeLedgerNeverShown();
    return _replayValue(
      entry,
      matchesLocal: _blockMapMatches(
        entry.decidedValue as Map<String, KdbxFieldPresent>?,
        currentLocal,
      ),
      matchesRemote: _blockMapMatches(
        entry.decidedValue as Map<String, KdbxFieldPresent>?,
        currentRemote,
      ),
    );
  }

  /// Replays a record-deletion decision. Keep/delete is always safe to
  /// replay: it names an operation, not a candidate.
  MergeLedgerReplay replayRecord(String objectUuid) {
    final entry = _records[objectUuid];
    if (entry == null) return const MergeLedgerNeverShown();
    return MergeLedgerReplayed(entry.choice);
  }

  MergeLedgerReplay _replayValue(
    MergeLedgerEntry entry, {
    required bool matchesLocal,
    required bool matchesRemote,
  }) {
    if (entry.choice != MergeChoice.local &&
        entry.choice != MergeChoice.remote) {
      // bothNotes/keep/delete: an operation, always safe to replay verbatim.
      return MergeLedgerReplayed(entry.choice);
    }
    if (entry.decidedValue == null) return const MergeLedgerStale();
    // The replay invariant is "decided value == whichever CURRENT side holds
    // it", not "decided value still on the side it was ORIGINALLY recorded
    // against" — the two candidates can swap which side carries the decided
    // value across a re-merge round (e.g. T401's apply step folds it into
    // local while a concurrent writer keeps moving remote), so the tag alone
    // is not enough. See spec.md FR-7 §"Explicit user decisions are sticky".
    if (matchesLocal) {
      return const MergeLedgerReplayed(MergeChoice.local);
    }
    if (matchesRemote) {
      return const MergeLedgerReplayed(MergeChoice.remote);
    }
    return const MergeLedgerStale();
  }

  bool _blockMapMatches(
    Map<String, KdbxFieldPresent>? decided,
    Map<String, KdbxFieldPresent> current,
  ) {
    if (decided == null) return false;
    if (decided.length != current.length) return false;
    for (final key in decided.keys) {
      final currentValue = current[key];
      if (currentValue == null || !decided[key]!.sameAs(currentValue)) {
        return false;
      }
    }
    return true;
  }
}
