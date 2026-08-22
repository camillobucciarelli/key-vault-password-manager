// spec-008 T202 — safe domain models for per-field sync conflict resolution.
//
// Everything in this file crosses the domain port and may therefore reach a
// coordinator, a BLoC state, a log line or an error report. Nothing here may
// carry a filesystem path, a KDBX object UUID, a checksum, a concurrency
// token, a credential, a field key, a field value or any handle that can be
// dereferenced into one. The transient plaintext response lives in
// `merge_field_display.dart` and is deliberately NOT exported from here, so a
// coordinator that imports this file cannot even name the type.
//
// The redaction contract is enforced structurally by
// `test/features/password_manager/domain/models/sync_merge_redaction_test.dart`,
// which parses this file and rejects any new field whose declared type or name
// is outside the safe set.
import 'package:equatable/equatable.dart';

/// Identity for one merge review session.
///
/// **What the shape check delivers, and what it does not.** The `ms-` prefix
/// plus a 32-hex body rejects a *bare* canonical path, a dashed KDBX UUID and a
/// bare MD5 handed over where an id was expected — the ordinary confusion of
/// passing the thing instead of its id. It is a typo guard, not a security
/// control, and it must not be read as one: an MD5 is itself exactly 32
/// lowercase hex, so `'ms-' + md5(path)` passes, and so does hex that decodes
/// straight back to a secret.
///
/// **Non-derivability is a property of minting, not of this type.** The token
/// must be drawn from a CSPRNG with at least 128 bits of entropy and never
/// derived from any input — path, UUID, checksum, credential or user value.
/// That obligation belongs to the data layer that mints it and is verified in
/// Gate 3 (`tasks.md` T302a); nothing in this class can enforce it, and this
/// comment does not claim otherwise.
///
/// The token is meaningless outside the data layer's private session store: a
/// lookup key, never a projection of the thing it identifies.
final class MergeSessionId extends Equatable {
  MergeSessionId(this.token) {
    if (!_pattern.hasMatch(token)) {
      throw ArgumentError.value(
        '<redacted>',
        'token',
        'Merge session id must be an "ms-" token of 32 lowercase hex '
            'characters. Shape only: this rejects a bare path/UUID/checksum '
            'passed by mistake, it does not prove the token is unpredictable '
            '(see T302a).',
      );
    }
  }

  static final RegExp _pattern = RegExp(r'^ms-[0-9a-f]{32}$');

  /// The opaque token. Safe to log, persist and compare: it is random and
  /// carries no information about the database, the file or its contents.
  final String token;

  @override
  List<Object?> get props => [token];

  @override
  String toString() => 'MergeSessionId(<opaque>)';
}

/// Identity for one reviewable decision.
///
/// A *command identity*, not a plaintext handle: it addresses a row in the data
/// layer's private session store. It must not be derived from the object UUID,
/// the field key or the attachment name — that is a **minting** obligation on
/// the data layer, verified in Gate 3 (`tasks.md` T302a). The shape check below
/// is a typo guard with the same limits as [MergeSessionId]'s.
final class MergeDecisionId extends Equatable {
  MergeDecisionId(this.token) {
    if (!_pattern.hasMatch(token)) {
      throw ArgumentError.value(
        '<redacted>',
        'token',
        'Merge decision id must be an "md-" token of 32 lowercase hex '
            'characters. Shape only: see MergeSessionId and T302a.',
      );
    }
  }

  static final RegExp _pattern = RegExp(r'^md-[0-9a-f]{32}$');

  final String token;

  @override
  List<Object?> get props => [token];

  @override
  String toString() => 'MergeDecisionId(<opaque>)';
}

/// Registry-level database identity (`DatabaseRecord.databaseId`), never a
/// filesystem path. FR-7 keeps canonical paths data-private.
///
/// The check is a heuristic on separators and the `.kdbx` suffix: it catches
/// the ordinary mistake, not a determined caller. `C:vault.kdb` and
/// `Users_me_Documents_Vault` both pass — tracked as F8.
final class MergeDatabaseId extends Equatable {
  MergeDatabaseId(this.value) {
    final looksLikePath =
        value.contains('/') ||
        value.contains(r'\') ||
        value.toLowerCase().endsWith('.kdbx');
    if (value.trim().isEmpty || looksLikePath) {
      throw ArgumentError.value(
        '<redacted>',
        'value',
        'Merge database id must be a registry id, never a filesystem path.',
      );
    }
  }

  final String value;

  @override
  List<Object?> get props => [value];

  @override
  String toString() => 'MergeDatabaseId(<redacted>)';
}

/// Where the session currently is. `needsReview` is reachable *after* a commit
/// attempt: FR-7 returns a session to review when a re-merge introduces a
/// conflict the user has never been shown.
enum MergeReviewPhase { reviewing, ready, committing, needsReview, terminal }

enum MergeDecisionKind {
  fieldConflict,
  fieldDeletionConflict,
  recordDeletionConflict,
  groupConflict,
}

enum MergeFieldCategory {
  title,
  username,
  password,
  url,
  notes,
  otp,
  customField,
  attachment,
  parentGroup,
  groupMetadata,
  other,
}

/// Which sides hold a value for this decision. One-sided *non-deletion* data is
/// never a decision at all (FR-4: it is an automatic union counted in the
/// summary), so `localOnly`/`remoteOnly` occur only where explicit deletion
/// evidence exists — enforced by [RedactedMergeDecision]'s constructor.
enum MergePresence { presentBoth, localOnly, remoteOnly }

enum MergeChoice { local, remote, bothNotes, keep, delete }

/// How the two sides' KDBX modification times relate, redacted to a relation so
/// no timestamp crosses the port.
///
/// FR-3 (defect N3): an unknown modification time is *not* a tie. Known beats
/// unknown, then newer wins, then the deterministic UTF-8 value order decides.
/// `tie` and `bothUnknown` are the two states the UI must mark as uncertain;
/// the resolved default is still globally deterministic and identical on both
/// devices.
enum TimestampRelation {
  localNewer,
  remoteNewer,
  tie,
  localKnownRemoteUnknown,
  remoteKnownLocalUnknown,
  bothUnknown,
}

/// One reviewable conflict, fully redacted.
///
/// Invariants enforced on construction (FR-4/FR-5/FR-6 — these are the
/// "missing side can never be selected" and "default is visible" rules made
/// structural rather than documented):
///
/// 1. a non-`presentBoth` presence requires explicit deletion evidence, i.e. a
///    deletion-conflict [kind];
/// 2. a deletion conflict is answered with `keep`/`delete` only, and a value
///    conflict with `local`/`remote`/`bothNotes` only — a deletion is never
///    inferred from absence, and a side is never selected as `null`;
/// 3. `local`/`remote` may only name a side that is actually present;
/// 4. `bothNotes` — the FR-3 ordered, deduplicated segment union — is available
///    on a Notes field conflict and nowhere else;
/// 5. an automatic default on a deletion conflict is `keep` (FR-5 "default
///    preserve"), so an unattended session can never delete.
final class RedactedMergeDecision extends Equatable {
  RedactedMergeDecision({
    required this.decisionId,
    required this.ordinal,
    required this.kind,
    required this.category,
    required this.presence,
    required this.choice,
    required this.isDefault,
    required this.timestampRelation,
  }) {
    final isDeletion =
        kind == MergeDecisionKind.fieldDeletionConflict ||
        kind == MergeDecisionKind.recordDeletionConflict;

    if (presence != MergePresence.presentBoth && !isDeletion) {
      throw ArgumentError(
        'A one-sided row without deletion evidence is an automatic union, not '
        'a decision (FR-4). Got $kind with $presence.',
      );
    }
    if (isDeletion &&
        choice != MergeChoice.keep &&
        choice != MergeChoice.delete) {
      throw ArgumentError(
        'A deletion conflict is answered with keep/delete only (FR-5). '
        'Got $choice.',
      );
    }
    if (!isDeletion &&
        (choice == MergeChoice.keep || choice == MergeChoice.delete)) {
      throw ArgumentError(
        'keep/delete require explicit deletion evidence (FR-4). Got $kind.',
      );
    }
    if (choice == MergeChoice.local && presence == MergePresence.remoteOnly) {
      throw ArgumentError('The missing local side cannot be selected (FR-4).');
    }
    if (choice == MergeChoice.remote && presence == MergePresence.localOnly) {
      throw ArgumentError('The missing remote side cannot be selected (FR-4).');
    }
    if (choice == MergeChoice.bothNotes &&
        (category != MergeFieldCategory.notes ||
            kind != MergeDecisionKind.fieldConflict)) {
      throw ArgumentError(
        'The deterministic both-sides segment union applies to a Notes field '
        'conflict only (FR-3). Got $kind/$category.',
      );
    }
    if (isDefault && isDeletion && choice != MergeChoice.keep) {
      throw ArgumentError(
        'The automatic default for a deletion conflict is keep (FR-5).',
      );
    }
    if (ordinal < 0) {
      throw ArgumentError.value(ordinal, 'ordinal', 'Must be non-negative.');
    }
  }

  final MergeDecisionId decisionId;

  /// Stable display position. Deliberately not a UUID and not a field key.
  final int ordinal;
  final MergeDecisionKind kind;
  final MergeFieldCategory category;
  final MergePresence presence;

  /// Always populated: every conflict carries a visible, pre-selected default
  /// so the review screen never shows an unanswered row (T206).
  final MergeChoice choice;

  /// True while [choice] is still the automatically computed default. Set to
  /// false by [withChoice] once the user answers — FR-7's ledger records both,
  /// so "accepted the default" is distinguishable from "never shown".
  final bool isDefault;
  final TimestampRelation timestampRelation;

  /// Records an explicit user answer. Re-runs every constructor invariant, so
  /// an illegal override (a missing side, a delete without evidence, a
  /// both-notes on a password) throws instead of reaching the data layer.
  RedactedMergeDecision withChoice(MergeChoice newChoice) {
    return RedactedMergeDecision(
      decisionId: decisionId,
      ordinal: ordinal,
      kind: kind,
      category: category,
      presence: presence,
      choice: newChoice,
      isDefault: false,
      timestampRelation: timestampRelation,
    );
  }

  @override
  List<Object?> get props => [
    decisionId,
    ordinal,
    kind,
    category,
    presence,
    choice,
    isDefault,
    timestampRelation,
  ];
}

/// The whole reviewable state of one merge session, redacted.
///
/// The one-sided counts are counts on purpose: FR-4 preserves one-sided records
/// and fields automatically, so the user is told *how much* survives without
/// any of it becoming addressable, and no shortcut can target it.
final class MergeReviewSummary extends Equatable {
  MergeReviewSummary({
    required this.sessionId,
    required this.databaseId,
    required this.phase,
    required List<RedactedMergeDecision> decisions,
    required this.localOnlyRecordCount,
    required this.remoteOnlyRecordCount,
    required this.oneSidedFieldCount,
  }) : decisions = List.unmodifiable(decisions) {
    for (final count in [
      localOnlyRecordCount,
      remoteOnlyRecordCount,
      oneSidedFieldCount,
    ]) {
      if (count < 0) {
        throw ArgumentError.value(count, 'count', 'Must be non-negative.');
      }
    }
    final ids = decisions.map((d) => d.decisionId).toSet();
    if (ids.length != decisions.length) {
      throw ArgumentError('Decision ids must be unique within a session.');
    }
  }

  final MergeSessionId sessionId;
  final MergeDatabaseId databaseId;
  final MergeReviewPhase phase;
  final List<RedactedMergeDecision> decisions;
  final int localOnlyRecordCount;
  final int remoteOnlyRecordCount;
  final int oneSidedFieldCount;

  /// FR-11: above this many conflicts the review shows shortcuts only.
  bool get exceedsPerDecisionReviewLimit => decisions.length > 200;

  @override
  List<Object?> get props => [
    sessionId,
    databaseId,
    phase,
    decisions,
    localOnlyRecordCount,
    remoteOnlyRecordCount,
    oneSidedFieldCount,
  ];
}

/// Safe outcome codes. No raw exception, path, checksum, token or user value.
enum MergeFailureCode {
  wrongLineage,
  unsupportedKdbxData,

  /// Distinct from [unsupportedKdbxData] (UUID integrity): a KDBX construct the
  /// adapter cannot preserve. Mandated by the T008 report's model corrections
  /// so a future refusal is reportable without leaking object labels.
  unsupportedKdbxConstruct,
  credentialsRevoked,
  staleLocal,
  staleRemote,
  staleRecoveryLocal,
  backupFailed,
  serializationParityFailed,
  atomicReplaceFailed,
  uploadRejected,
  uploadOutcomeAmbiguous,
  uploadConflict,

  /// FR-7: the divergence retry budget (3) or the review re-entry cap (3) was
  /// exhausted. The merged local file and the dated backup are retained and the
  /// mapping is not marked synced.
  unresolvedConflict,
  cancelled,
  sessionInvalidated,
  platformDisabled,
}

/// FR-10: an apparent success is not terminal. `uploaded` is only reported
/// after the FR-7 step-5 read-back confirmed the remote holds the merged bytes.
enum MergeUploadState { uploaded, pendingRecovery }

sealed class MergeCommitOutcome extends Equatable {
  const MergeCommitOutcome();
}

final class MergeApplied extends MergeCommitOutcome {
  const MergeApplied({
    required this.entryCount,
    required this.backupCreated,
    required this.uploadState,
  });

  final int entryCount;
  final bool backupCreated;
  final MergeUploadState uploadState;

  @override
  List<Object?> get props => [entryCount, backupCreated, uploadState];
}

/// FR-7: an automatic re-merge surfaced a conflict the user has never been
/// shown. Nothing further is written and the session goes back to review
/// carrying the earlier decisions plus the new conflicts.
final class MergeNeedsReview extends MergeCommitOutcome {
  const MergeNeedsReview({
    required this.summary,
    required this.newConflictCount,
    required this.reviewReentryCount,
  });

  final MergeReviewSummary summary;

  /// How many of [summary]'s decisions the user has never seen.
  final int newConflictCount;

  /// How many times this session has already returned to review. Capped at 3
  /// (FR-7 N2); the fourth attempt ends as [MergeFailureCode.unresolvedConflict].
  final int reviewReentryCount;

  @override
  List<Object?> get props => [summary, newConflictCount, reviewReentryCount];
}

final class MergeRejected extends MergeCommitOutcome {
  const MergeRejected(this.code, {required this.localCommitCompleted});

  final MergeFailureCode code;

  /// True once the atomic local replace has been dispatched: FR-8 forbids an
  /// automatic rollback past that boundary, so the UI must not offer one.
  final bool localCommitCompleted;

  @override
  List<Object?> get props => [code, localCommitCompleted];
}

enum MergeRecoveryDisposition {
  none,
  finalizedApplied,
  retriedAndFinalized,
  staleRecoveryLocal,
  needsNewConflict,
  stillAmbiguous,
}

final class MergeRecoveryOutcome extends Equatable {
  const MergeRecoveryOutcome(this.disposition);

  final MergeRecoveryDisposition disposition;

  @override
  List<Object?> get props => [disposition];
}
