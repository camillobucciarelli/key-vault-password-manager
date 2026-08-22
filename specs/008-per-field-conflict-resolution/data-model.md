# 008 — Data model

## Freeze rule

**FROZEN 2026-08-22 (T201).** Gate 0 closed on 2026-08-21 with T001–T009 passed
and PM-accepted; T009b was accepted on 2026-08-22. This document is now the
domain contract Phase 3 implements against, not a sketch.

It was frozen **from `feasibility-report.md`**, which is the executed evidence.
Where this document and the report disagreed, the report won and the change is
recorded in "T201 freeze log — divergences resolved" at the end of this file.
Where the report is silent and `spec.md`/`tasks.md` are not, the spec text wins
and the choice is recorded there too. Nothing in this document is derived from
an assumption that has no executed evidence behind it.

Changing a frozen declaration is a spec amendment: edit `spec.md`, re-run the
affected Gate 0 model, then edit this file. Adding **any declaration at all** to
a registered merge file additionally has to pass
`test/features/password_manager/domain/models/sync_merge_redaction_test.dart`,
and adding a **file** to the merge module has to pass the registry-completeness
check in `sync_merge_domain_architecture_test.dart`: a file in `lib/` that names
a spec-008 merge identifier and is absent from
`test/features/password_manager/domain/sync_merge_module_registry.dart` fails
the suite. Forgetting the registry is a failure, not a silent pass.

The judge behind both gates is **fail-closed**: a top-level declaration, class
member, type annotation or directive whose kind it does not recognise is a
violation, not a skip. A Dart construct that does not exist today will therefore
break this gate the first time it is used in the module, and a human will decide
what it means. That is deliberate, and it is the correction for the defect that
survived two review rounds in different disguises — see "Validation history".

Representation split:

1. domain opaque/redacted command and view models;
2. data-private full-fidelity KDBX/session/recovery models.

`VaultSnapshot` is not merge write source.

## Domain port

Lives in
`lib/features/password_manager/domain/repositories/sync_merge_repository.dart`.
No data imports.

```dart
abstract interface class SyncMergeRepository {
  Future<MergeReviewSummary> startReview(MergeDatabaseId databaseId);

  Future<MergeReviewSummary> updateDecision({
    required MergeSessionId sessionId,
    required MergeDecisionId decisionId,
    required MergeChoice choice,
  });

  Future<MergeCommitOutcome> commit(MergeSessionId sessionId);
  Future<void> cancel(MergeSessionId sessionId);
  Future<void> invalidate(MergeDatabaseId databaseId);
  Future<MergeRecoveryOutcome> recoverPending(MergeDatabaseId databaseId);

  Future<MergeFieldDisplay> loadFieldDisplay({
    required MergeSessionId sessionId,
    required MergeDecisionId decisionId,
  });
}

/// The only error the port raises. Safe code, nothing else.
final class SyncMergeFailure implements Exception {
  const SyncMergeFailure(this.code, {this.localCommitCompleted = false});

  final MergeFailureCode code;
  final bool localCommitCompleted;
}
```

`startReview` has no outcome type, so lineage and UUID-integrity refusals
(`wrongLineage`, `unsupportedKdbxData`, `unsupportedKdbxConstruct`) surface as
`SyncMergeFailure` — before any session id, backup, local write or upload
exists.

Focused domain use cases wrap each method, one class per operation, in
`domain/usecases/sync_merge_usecases.dart`. `SyncMergeCoordinator` depends on
those command use cases only. The field widget depends directly on
`LoadSyncMergeFieldDisplayUseCase`, which lives in its **own library**
(`domain/usecases/load_sync_merge_field_display_usecase.dart`) precisely so that
importing the command use cases does not bring `MergeFieldDisplay` into scope.
Coordinator and BLoC never see its plaintext result.

### Opaque identifiers

```dart
final class MergeSessionId extends Equatable {  // token: ^ms-[0-9a-f]{32}$
final class MergeDecisionId extends Equatable { // token: ^md-[0-9a-f]{32}$
final class MergeDatabaseId extends Equatable { // registry id, never a path
```

The ids are **types, not `String`s**, and each validates its shape on
construction.

**What the shape check delivers.** It rejects a *bare* canonical path, a dashed
KDBX UUID and a bare MD5 handed over where an id was expected — the ordinary
confusion of passing the thing instead of its id. `MergeDatabaseId` likewise
refuses a value containing a separator or ending in `.kdbx`, because FR-7 keeps
canonical paths data-private.

**What it does not deliver, stated here because the first version of this
document claimed otherwise.** The check is a **typo guard, not a security
control**. An MD5 is itself exactly 32 lowercase hex, so `'ms-' + md5(path)`
passes; `'ms-' + md5('hunter2')` passes; `ms-7573657240636f72702e636f6d212121`
passes and decodes straight back to `user@corp.com!!!`; an undashed KDBX UUID
passes. The `MergeDatabaseId` heuristic accepts `C:vault.kdb` and
`Users_me_Documents_Vault` (F8). Three assertions in the redaction test record
these acceptances as executable facts, so the limit cannot quietly be forgotten
again.

**Where the guarantee actually lives.** Non-derivability is a property of
**minting**, not of the type: the token must be drawn from a CSPRNG with at
least 128 bits of entropy and never derived from any input. That is a data-layer
obligation, and it is verified in Gate 3 by **`tasks.md` T302a**. It is recorded
there rather than asserted here, because Phase 2 contains no minting code and a
frozen contract must not promise what its types do not enforce.

`toString` on all three is redacted, and their `ArgumentError` messages report
`<redacted>` rather than echoing the rejected value.

## Domain-safe models

### `MergeReviewSummary`

```dart
enum MergeReviewPhase { reviewing, ready, committing, needsReview, terminal }

final class MergeReviewSummary extends Equatable {
  MergeReviewSummary({
    required this.sessionId,
    required this.databaseId,
    required this.phase,
    required List<RedactedMergeDecision> decisions,
    required this.localOnlyRecordCount,
    required this.remoteOnlyRecordCount,
    required this.oneSidedFieldCount,
  }) : decisions = List.unmodifiable(decisions);

  final MergeSessionId sessionId;
  final MergeDatabaseId databaseId;
  final MergeReviewPhase phase;
  final List<RedactedMergeDecision> decisions;
  final int localOnlyRecordCount;
  final int remoteOnlyRecordCount;
  final int oneSidedFieldCount;

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
```

No path, root/object UUID, checksum, Drive token, credential, KDBX type, raw field
name/value, attachment bytes/hash derived from secret data, or plaintext handle.

Counts are counts on purpose: FR-4 preserves one-sided records and fields
automatically, so the user is told *how much* survives without any of it being
addressable — and therefore without any shortcut being able to reach it.

`phase` reaches `needsReview` **after** a commit attempt: FR-7 returns a session
to review when an automatic re-merge surfaces a conflict the user has never been
shown. `bool get exceedsPerDecisionReviewLimit => decisions.length > 200`
carries FR-11's shortcuts-only threshold in the model instead of in the widget.
Construction rejects negative counts and duplicate decision ids.

### `RedactedMergeDecision`

```dart
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

enum MergePresence { presentBoth, localOnly, remoteOnly }

enum MergeChoice { local, remote, bothNotes, keep, delete }

/// FR-3 defect N3: an unknown modification time is NOT a tie. Known beats
/// unknown, then newer wins, then the deterministic UTF-8 value order decides.
enum TimestampRelation {
  localNewer,
  remoteNewer,
  tie,
  localKnownRemoteUnknown,
  remoteKnownLocalUnknown,
  bothUnknown,
}

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
  });

  final MergeDecisionId decisionId; // command identity, not a plaintext handle
  final int ordinal;
  final MergeDecisionKind kind;
  final MergeFieldCategory category;
  final MergePresence presence;
  final MergeChoice choice;
  final bool isDefault;
  final TimestampRelation timestampRelation;

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
```

Automatic one-sided fields are summary rows, not decisions, so shortcut cannot
target them. Custom field names and attachment names remain data-private until
one transient display is requested.

**The FR-4/FR-5/FR-6 rules are constructor invariants, not documentation.**
`RedactedMergeDecision` throws on construction — and `withChoice` re-runs every
check, so an override is validated too — when:

1. `presence != presentBoth` on a non-deletion kind. A one-sided row without
   deletion evidence is an automatic union, so it is *unrepresentable* as a
   decision and therefore unreachable by a shortcut, by construction rather than
   by the shortcut remembering to skip it;
2. a deletion conflict is answered with anything but `keep`/`delete`, or a value
   conflict with `keep`/`delete`. A delete always needs explicit evidence and is
   never inferred from absence;
3. `local` names a `remoteOnly` row or `remote` names a `localOnly` row — the
   missing side can never be selected, and `null` is never a choice;
4. `bothNotes` appears anywhere but a Notes `fieldConflict`;
5. an *automatic default* on a deletion conflict is not `keep` (FR-5 "default
   preserve"), so an unattended session can never delete.

`choice` is always populated and `isDefault` says whether it is still the
computed default: FR-7's ledger records "accepted the default" and "never shown"
as different facts, and N2 turns the difference into a review loop if it is
lost.

`SyncMergePolicy` (`domain/services/sync_merge_policy.dart`) is the pure
companion: `availableChoicesFor(decision)` is the UI's affordance set, and
`commandsFor(summary, shortcut)` is FR-6's shortcut, which iterates
`summary.decisions` and nothing else. On a deletion conflict a shortcut maps the
**preferred side's own state** to keep or delete — preferring the side that
holds the record keeps it, preferring the side that deleted it deletes it —
which is FR-4's "maps side state to explicit `keep`/`delete`; it never infers
delete from absence".

### `MergeFieldDisplay`

Transient plaintext presentation response for one visible decision:

```dart
final class MergeFieldDisplay {
  MergeFieldDisplay({
    required String label,
    required this.local,
    required this.remote,
    required this.protected,
  });

  String get label;               // throws once disposed
  final MergeDisplaySide local;
  final MergeDisplaySide remote;
  final bool protected;
  bool get isDisposed;

  void dispose();                 // drops references on unmount / lock

  @override
  String toString() => 'MergeFieldDisplay(<redacted>)';
}

final class MergeDisplaySide {
  MergeDisplaySide.present(
    String value, {
    DateTime? changedAt,
    int? sizeBytes,      // attachments only
    String? fingerprint, // attachments only, never the bytes
  });

  MergeDisplaySide.missing();

  final bool isPresent;
  String? get value;        // throws once disposed
  DateTime? get changedAt;
  int? get sizeBytes;
  String? get fingerprint;
  bool get isDisposed;

  void dispose();

  @override
  String toString() => 'MergeDisplaySide(<redacted>)';
}
```

Not `Equatable`, not serializable, never in coordinator/BLoC/state/navigation or
logs. Widget owns response only while card mounted and clears on dispose/lock.
Missing side constructor is for display only; it is never selectable unless
decision is explicit deletion conflict and command is `delete`.

Attachment display contains name/size/hash prefix but never bytes. Data store
keeps exact bytes.

**How this is kept out of a state, structurally rather than by review.** The
type lives in its own library, `domain/models/merge_field_display.dart`, which
`sync_merge_models.dart` neither imports nor exports. Dart imports are not
transitive, so a coordinator or BLoC that imports the safe models, the port or
the command use cases **cannot name `MergeFieldDisplay` at all** — holding one
would require adding an import, and
`test/features/password_manager/domain/sync_merge_domain_architecture_test.dart`
fails on any importer outside a three-entry allowlist (the port, its use case,
and — from Phase 6 — the field widget). On top of that, the redaction test
parses the file and rejects any class here that gains a superclass, a `props`
getter, a serializer, or a `toString` that interpolates instead of returning a
constant literal.

Fields are private and nullable so `dispose()` can actually drop them; a read
after disposal throws `StateError` rather than returning stale plaintext. Dart
cannot guarantee zeroization — constitution principle I — so this minimizes the
number and lifetime of live references and claims nothing more.

### Outcomes

```dart
enum MergeFailureCode {
  wrongLineage,
  unsupportedKdbxData,
  unsupportedKdbxConstruct, // T008 model correction: distinct from UUID integrity
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
  unresolvedConflict, // FR-7: retry budget (3) or review re-entry cap (3) spent
  cancelled,
  sessionInvalidated,
  platformDisabled,
}

/// FR-10: `uploaded` means the step-5 read-back CONFIRMED the remote holds the
/// merged bytes. An apparent success is never reported as `uploaded`.
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

/// FR-7 (C3/N2): an automatic re-merge surfaced a conflict never shown to the
/// user. Nothing further is written; the session goes back to review carrying
/// the earlier decisions plus the new conflicts.
final class MergeNeedsReview extends MergeCommitOutcome {
  const MergeNeedsReview({
    required this.summary,
    required this.newConflictCount,
    required this.reviewReentryCount, // capped at 3
  });

  final MergeReviewSummary summary;
  final int newConflictCount;
  final int reviewReentryCount;

  @override
  List<Object?> get props => [summary, newConflictCount, reviewReentryCount];
}

final class MergeRejected extends MergeCommitOutcome {
  const MergeRejected(this.code, {required this.localCommitCompleted});

  final MergeFailureCode code;
  final bool localCommitCompleted;

  @override
  List<Object?> get props => [code, localCommitCompleted];
}
```

No raw exception, database/backup/key path, checksum/token or user value in
outcome.

## Field-level presence model

Data-private comparison tracks `FieldPresence.present(value)` separately from
`FieldPresence.missing`; present empty string and present zero bytes are not
missing.

| Local | Remote | Explicit deletion evidence | Domain summary | Apply rule |
| --- | --- | --- | --- | --- |
| present equal | present equal | none | no decision | preserve |
| present different | present different | none | `fieldConflict` | chosen present side |
| present | missing | none | automatic local-only field count/row | preserve local |
| missing | present | none | automatic remote-only field count/row | preserve remote |
| missing | missing | none | none | emit absent |
| present | missing | remote marker | `fieldDeletionConflict` | explicit keep/delete, default keep |
| missing | present | local marker | `fieldDeletionConflict` | explicit keep/delete, default keep |

KDBX custom field and attachment absence normally supplies no deletion marker;
union wins. `preferSide` iterates decisions only. It never emits `local`/`remote`
choice whose side is missing. For explicit deletion conflict it emits
`keep`/`delete`, never null.

Data tests must include same entry UUID with:

- custom field local-only, remote-only, empty-vs-missing and protected status;
- attachment local-only, remote-only, zero-byte-vs-missing, equal name/different
  bytes and protection property;
- both shortcuts and every other decision proving one-sided data survives.

## Record deletion model

| Local evidence | Remote evidence | Classification | Default/output |
| --- | --- | --- | --- |
| live | absent, no tombstone | record local-only | preserve live |
| absent, no tombstone | live | record remote-only | preserve live |
| live | recycle bin | deletion conflict | keep unless explicit delete/move-to-bin |
| recycle bin | live | deletion conflict | keep unless explicit delete/move-to-bin |
| live | tombstone | deletion conflict | keep or tombstone, explicit |
| tombstone | live | deletion conflict | keep or tombstone, explicit |
| recycle bin | recycle bin | deleted | preserve supported newest metadata |
| tombstone | tombstone | deleted | preserve supported union/newest tombstone |
| missing | missing | none | no object |

Keep removes/neutralizes matching tombstone. Delete emits no live/recycle object
and valid tombstone. Ambiguous/unsupported evidence aborts.

## Data-private models

Live only in
`lib/features/password_manager/data/repositories/sync_merge_repository_impl.dart`
and adapter/services. No `Equatable`, JSON or useful `toString`.

### `_KdbxMergeSession`

```text
opaque sessionId
databaseId + canonical database identity/path
local/remote KdbxFile
credentials and key-file bytes for shortest required lifetime
semantic manifests
validated root/object UUID maps (non-nil, globally unique live objects)
decisionId -> private object/field key + values/presence/deletion evidence
local checksum + remote checksum/token
session generation + commit boundary
```

Data repository owns `_sessions`. Coordinator owns only matching opaque ID and
redacted decision commands. Cancel, lock, database switch, completion and stale
generation dispose session references.

### `KdbxSemanticManifest`

Canonical private structure:

```text
version/header/KDF/compression/cipher
root UUID
metadata/settings/custom data/icons
groups: UUID, parent/order, all fields/times/icon/custom data
entries: UUID, parent, strings with presence/protection, times/attributes
attachments: name, SHA-256, length, exact bytes in test comparison,
             inline/reference/protection
history revisions
recycle-bin state/members
tombstones UUID/deletion metadata
```

Semantic validation distinguishes missing/empty and plain/protected.

Before diff, adapter builds one global live-object UUID index per side across root,
groups and entries. Nil UUID, duplicate entry UUID, duplicate group UUID, any
group-entry collision, or same cross-side UUID with different object kind returns
`unsupportedKdbxData`. No session is inserted into `_sessions`; no write/upload
occurs.

### `_PendingMergeUpload`

Persisted before request dispatch so restart can recover:

```text
databaseId
canonical path or recoverable database reference (data-private persistence)
merged checksum
localCommittedChecksum (exact bytes after atomic local commit)
expected old remote checksum
expected old remote conditional token
drive file ID
backup path (data-private)
createdAt
state: pendingDispatch | outcomeAmbiguous | staleRecoveryLocal | needsNewConflict
```

No plaintext or credentials. It is not exposed through domain port.

### Recovery result

```dart
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
```

Recovery algorithm acquires `DatabasePathMutex` first. Before remote fetch/triage
or any vault mutation, it hashes current local bytes:

| Check | Meaning | Action |
| --- | --- | --- |
| current local checksum != `localCommittedChecksum` | local changed after persisted commit | return `staleRecoveryLocal`; no upload/retry/finalization/mapping-success update/vault mutation; retain backup + pending evidence; require fresh conflict |
| current local checksum == `localCommittedChecksum`; remote checksum == merged checksum | request applied (or equivalent merged content present) | finalize mapping from fresh metadata, clear pending |
| local matches; remote checksum + token == expected old values | request not applied | retry same conditional upload; then verify |
| local matches; any third remote state | independent remote change | retain local+backup, start new conflict, no blind retry |

HTTP conditional rejection is certain not applied. Transport timeout/disconnect
after dispatch sets `outcomeAmbiguous`; never plain `uploadFailed`. Startup calls
`recoverPending(databaseId)` under database mutex before auto-sync. Restart tests
must mutate local file after pending record persistence and prove
`staleRecoveryLocal` occurs before remote client call or any mutation.

## Database path identity/lock model

Data-only `DatabasePathIdentity` contains canonical comparison key, optional
platform file identity and an explicit **`identityConfidence`** flag (T008 model
correction). It never enters domain/presentation. Where confidence is not
`proven`, the platform falls back to one coarse global database lock rather than
to unsafe per-path concurrency. T103 resolved the mechanism as a per-volume
**runtime probe**, not a per-platform table.

Resolution covers absolute/relative, separator normalization, `.`/`..`, symlink
resolution, real parent for nonexistent target, platform case semantics and hard
links. Platform lacking reliable alias identity uses one global database lock.

`lockAll(paths)` resolves/deduplicates/sorts identities before acquisition. Rename
locks old+new in same call and holds through metadata updates/rollback.

## Backup model

Backup final name:

```text
<database-name>.<yyyyMMdd-HHmmss-ffffff>.<suffix>.pre-merge.kdbx
```

`suffix` is random or monotonic collision counter. Temp and final open use
exclusive-create/no-overwrite semantics. Collision chooses new suffix; never
truncates existing backup. Verified backup checksum/size required before target
temp write.

## Coordinator/BLoC state

Coordinator state:

```text
opaque sessionId
redacted decisions
sequence: idle | reviewing | ready | committing | terminal
```

BLoC state may mirror safe summary/outcome. Neither stores
`MergeFieldDisplay`, private session, preconditions, credentials, paths, UUIDs,
checksums/tokens or plaintext handles.

## Semantic shortcut assertions

Reopened output under both shortcuts must have:

- unchanged root UUID/credentials;
- union of record-level and field-level one-sided data;
- chosen present value for true conflicts;
- no choice of missing/null side;
- explicit deletion result only where evidence exists;
- unchanged unrelated history, metadata/settings, icons, attachments and
  tombstones;
- no unexplained manifest delta.

Ciphertext bytes, salts/IVs and documented serializer order are non-semantic.

## T201 freeze log — divergences resolved

Frozen 2026-08-22 against `feasibility-report.md`. Every row below is a place
where this document and the executed evidence (or the corrected `spec.md` the
evidence produced) did not say the same thing. Each is resolved toward the
report; where the report is silent, toward `spec.md`/`tasks.md`, and that is
stated. Nothing was resolved toward the older text of this file.

| # | Divergence | Resolution | Authority |
| --- | --- | --- | --- |
| **D1** | The freeze rule read "provisional until T001–T008 pass". Gate 0 in fact closed on **T009**, which did not exist when this line was written. | Freeze rule rewritten: Gate 0 closed 2026-08-21 on T001–T009, PM-accepted; T009b accepted 2026-08-22. | report §Sign-off |
| **D2** | `MergeFailureCode` had no code for a construct the adapter cannot preserve, only the UUID-integrity `unsupportedKdbxData`. | Added `unsupportedKdbxConstruct`. The report mandates the distinction verbatim, so a future refusal is reportable without leaking object labels. | report §"Model corrections from spike" |
| **D3** | The path-identity section did not name the `identityConfidence` concept the report requires for the mutex layer. | Added, data-only, never in domain; with T103's per-volume runtime probe recorded. | report §"Model corrections from spike", §"Path identity design" |
| **D4** | `RedactedMergeDecision.timestampRelation` was typed `TimestampRelation`, which **no section of this document defined**. | Defined with six values. Critically it distinguishes known-vs-unknown timestamps: defect N3 proved that treating an unknown time as a bare tie makes the order non-transitive, so a two-valued or three-valued relation would have frozen the defect into the contract. | report N3, `spec.md` FR-3 |
| **D5** | `MergeReviewSummary.phase` was typed `MergeReviewPhase`, also **never defined**; and FR-7 gained a post-commit return-to-review state after this file was written. | Defined as `reviewing, ready, committing, needsReview, terminal`. | report N2/C3, `spec.md` FR-7 |
| **D6** | `MergeCommitOutcome` had exactly two variants, so FR-7's "the session returns to review" and "ends as an unresolved conflict" had **no representation** — a commit could only be applied or rejected. | Added `MergeNeedsReview(summary, newConflictCount, reviewReentryCount)` and `MergeFailureCode.unresolvedConflict` (retry budget 3, review re-entry cap 3). Without these the sticky-decision correction C3 and the N2 caps are unimplementable against the frozen port. | report C3, C7, N2 |
| **D7** | Session and decision ids were frozen as bare `String`. `tasks.md` T202 requires ids that are opaque and not derivable into sensitive values. | Introduced `MergeSessionId` / `MergeDecisionId` / `MergeDatabaseId` as types with a shape check. **Corrected 2026-08-22 after review:** the first version of this row claimed the shape made the ids non-derivable, and that is false — a prefixed MD5 is 32 hex and passes, as does hex that decodes back to a secret. The shape is a typo guard; the non-derivability half of T202 is discharged by a **minting** requirement on the data layer, added as **T302a** and verified in Gate 3. The claim was moved rather than deleted so the requirement survives, and the acceptances are now pinned by executable assertions. | `tasks.md` T202, T302a |
| **D8** | `databaseId` was untyped and this document never said whether it is the registry id or the canonical path — and the existing `DatabaseSyncRepository` keys its mappings **by path**, so the ambiguity was live. | `MergeDatabaseId` is the registry `DatabaseRecord.databaseId`. A value containing a separator or ending in `.kdbx` is rejected on construction, because FR-7 keeps canonical paths data-private. | `spec.md` FR-7, existing `DatabaseRecord` |
| **D9** | `MergeChoice.bothNotes` predates defects N1 and Q1: at the time it meant a concatenation. | Name kept, semantics restated: the FR-3 **ordered, deduplicated union of segments** split on the `"\n\n---\u241E---\n\n"` sentinel and sorted by the same UTF-8 comparator as the tie-break. A fixed-order concatenation is non-associative and duplicates user text at three devices. | report N1, Q1 |
| **D10** | This document said nothing about the tie-break, which FR-3 now fixes as an unsigned lexicographic comparison of **UTF-8** bytes (defect R1: UTF-16 `codeUnits` is a *different* total order and elects opposite winners on astral characters). | Recorded as explicitly data-layer-only. No domain surface: the candidate values never cross the port, so the domain sees only `TimestampRelation` and the resolved default. | report R1, `spec.md` FR-3 |
| **D11** | `MergeDisplaySide` was declared `const` with `final` fields, which **cannot implement** the same document's requirement that the widget "clears on dispose/lock". | Fields are private and nullable; `dispose()` drops them and a later read throws `StateError`. Dart cannot zeroize, so the claim is minimized lifetime, not erasure. | `spec.md` §"Architecture and secret boundary", constitution I |
| **D12** | `MergeUploadState.uploaded` was written when a `2xx` was "definite success". | Restated: `uploaded` is reported only after the FR-7 step-5 read-back confirmed the bytes. An apparent success is never terminal. | report C5, `spec.md` FR-10 |
| **D13** | The attachment display had prose ("name/size/hash prefix, never bytes") but **no fields** to carry it. | `MergeDisplaySide` gains `sizeBytes` and `fingerprint`, attachment-only, never bytes. | this document's own §`MergeFieldDisplay` |
| **D14** | FR-11's ">200 conflicts shows shortcuts only" had no model surface, so the threshold would have been duplicated in the widget. | `MergeReviewSummary.exceedsPerDecisionReviewLimit`. | `spec.md` FR-11 |
| **D15** | `startReview` returns a summary and has no outcome type, so FR-2/FR-4 pre-session refusals had **no way to be reported** through the frozen port. | Added `SyncMergeFailure`, carrying a safe code and the post-boundary flag and nothing else. | `spec.md` FR-2, FR-8 |

Two things were considered and deliberately **not** added, so that their absence
reads as a decision rather than an oversight:

- **the backend guarantee tier** (`spec.md` §"Guarantee by backend category").
  It is not a field on `MergeReviewSummary`. Acceptance criterion 15c requires
  that *no domain or presentation code branches on a capability*; the tier is
  declared by the storage adapter and is **spec 010's** surface to report.
  Putting it in 008's merge summary would create exactly the branch 15c
  forbids;
- **a deletion-evidence model beyond `keep`/`delete`.** T009b's gaps G1–G4 —
  a tombstone matches only when strictly newer than the live mtime, Keep
  re-emits at the tombstone's clock, an equal clock breaks toward preservation,
  and a Keep/Delete decision does not propagate to peers — are all resolved
  inside the **evidence join**, which is a data-layer algebra. The domain needs
  only the explicit choice, which it already has. G4 in particular means each
  device decides for itself, and that is a property of the session ledger's
  lifetime, not of a domain type.

### What the freeze is enforced by

Not by review. `flutter analyze` is clean and these run with **no data
implementation in existence**:

| Artifact | Enforces |
| --- | --- |
| `test/.../domain/sync_merge_module_registry.dart` | **The single point of update.** Declares which files are in the merge module and which bucket each belongs to. Not a test itself; both gates derive their scope from it. |
| `test/.../domain/sync_merge_domain_architecture_test.dart` | **Registry completeness**: any file in `lib/` naming a spec-008 merge identifier and missing from the registry fails, so a new merge file cannot escape the gates. Exemptions are `(identifier, owning file)` pairs, never bare names. Plus: every registered file must live under `domain/`; the transient bucket is asserted to be a closed singleton, so it cannot be used as an opt-out; importer restrictions are derived from the transient bucket rather than from a literal filename; no merge file imports `data/`, `presentation/`, `dart:io` or Flutter; no `SyncMergeRepositoryImpl` or `KdbxMergeAdapter` exists. |
| `test/.../domain/sync_merge_ast_gate.dart` | **The fail-closed judge.** Walks classes, enums, mixins, extensions, extension types, typedefs, top-level functions and variables — and refuses any other top-level construct, any unrecognised class member, any unrecognised type-annotation shape and any directive other than `import`/`library`. `part` and `export` are refused outright. Types are judged on the AST, so nullability cannot change the verdict; `List`/`Set` recurse, record types recurse, function types are refused, and a parameterised type the judge cannot unwrap is refused. |
| `test/.../domain/models/sync_merge_redaction_test.dart` | Runs the judge over **every registered file**, strict for buckets 1 and 3: each field, getter, static and extension-type representation must have a safe type and a safe name, with `String` legal only at three listed ids; methods are judged **by return type**. The safe *stored* type set is built from the strict files **minus the transient bucket's own types**, so no field may hold a `MergeFieldDisplay` even though the port may return one. Safe models must be `Equatable` with `props`; the transient library must have no supertype, no `props`, and a `toString` that is a constant redacted literal. Plus runtime assertions on `props`/`toString`, on disposal, and on the exact limits of the id shape check. |
| `test/.../domain/services/sync_merge_policy_test.dart` | Visible defaults, deterministic both-sides notes, the shortcut set excluding one-sided rows, and the missing side being unselectable. |
| `test/.../domain/usecases/sync_merge_usecases_test.dart` | The port and its use cases compile and behave against a fake repository declared in the test file. |

### Validation history

Two rounds. The first found nothing wrong with the *contract* and everything
wrong with its *enforcement*, which is the part Gate 2 hands to Phase 3.

**Round 1 — author, 3 mutations, all killed.** A raw `String canonicalPath`
field on a safe model, a superclass on `MergeFieldDisplay`, and a
non-allowlisted file importing the transient display.

**Round 2 — independent tester, 15 mutations, 6 survived.** The verdict was NOT
VALIDATED, and it was correct: the two gates read hardcoded file lists, so the
sentences this document used to contain — "enforces the redaction contract
structurally" and "fails here without anyone remembering to extend a list" —
were false as written. All six are closed and each was re-verified by replaying
the tester's exact mutant:

| # | Survivor | Closure | Re-verified |
| --- | --- | --- | --- |
| **F1** | Both gates used literal file arrays, so a **new** `domain/models/sync_merge_extra_models.dart` carrying `canonicalPath`, `localChecksumMd5`, `masterPassword`, a `String Function()` plaintext reveal, `toJson`, `File get vaultFile`, `dart:io` and a `data/` import — exposed on the frozen port via an extension — passed the entire suite. | Scope derives from the registry, and registry completeness is enforced against all of `lib/` by identifier match. | Killed unregistered (completeness) **and** killed when registered (6 field/getter violations + the `toJson` return type + the `dart:io`/`data/` imports). |
| **F2** | The field rules ran on the models file only, so `SyncMergeFailure` — the object that reaches logs and crash telemetry — carried `masterPassword`, `localChecksumMd5` and `conflictingFieldLabel`, interpolated into `toString`. The old mutation died only on an incidental `isNot(contains('/'))`, so any secret without a slash passed. | The field/getter/static rules run on every strictly-redacted registry file. | Killed, 3 violations. |
| **F3** | Only `FieldDeclaration` was walked and statics were skipped, so `String get canonicalPath => value` on `MergeDatabaseId` and a process-wide `static final Map<String, String> plaintextByToken` on `RedactedMergeDecision` both passed. | Getters and statics are walked; a private static may only be a `RegExp`. | Killed, 4 violations. |
| **F4** | The serializer gate was a six-name blacklist, so `Map<String, dynamic> asTelemetryPayload()` passed. | Methods are judged by **return type**. | Killed. |
| **F5** | This document claimed the id shape made the ids non-derivable. False: `'ms-' + md5(path)` is accepted. | Claim struck and replaced with what the shape actually delivers; the guarantee relocated to minting requirement **T302a** in Gate 3; the acceptances pinned by assertions. | Documented, not mutated. |
| **F6** | The "three layers" protecting `MergeFieldDisplay` are really one — an allowlisted file may still copy `.value` into a durable `String`. | Registered as a **Phase 6 gate condition** on `tasks.md` T603; not implemented now, because no allowlisted consumer exists yet. | Deferred by decision. |

**Round 3 — independent tester, second NOT VALIDATED.** F1–F5 were confirmed
genuinely closed (6/6 of the previous survivors died, including the strongest
case: renaming every identifier innocuously still fails, because *using* the
transient type is enough to make a file a module member). The verdict was on the
gate's **design**, and it was the same defect as round 1 wearing different
clothes: round 1 enumerated *files*, round 2 enumerated *AST declaration kinds*.
The tester's sentence is the one that matters — *"as long as the walker
enumerates what it knows instead of refusing what it does not, this conversation
repeats at round four."*

The fix is therefore not the seven items below; it is that **the judge is now
fail-closed**, and the items are what that change had to cover:

| # | Escape | Closure | Re-verified |
| --- | --- | --- | --- |
| **N1** | `moduleDeclaredTypes()` iterated `mergeModuleFiles`, which *includes* the transient bucket, so `MergeDisplaySide` and `MergeFieldDisplay` — the two plaintext-bearing classes — counted as safe types for the strict bucket. `SyncMergeFailure` could hold a live `MergeDisplaySide` and a `List<MergeFieldDisplay>`: F2 reopened through the type system. | The safe *stored* set is built from the strict files and the transient type names are subtracted. Types are compared on the AST, so `MergeDisplaySide?` and `MergeDisplaySide` get the same verdict — previously nullability saved it by accident. | Killed, 2 violations. |
| **N2/N3** | Both walkers did `whereType<ClassDeclaration>()`. An enum with `canonicalPath`/`masterPassword`, `toJson` and a plaintext getter reachable as `uploadState.masterPassword`; an `extension type MergeVaultLocator(String canonicalPath)`; `typedef MergeSecretBundle = Map<String, String>`; and worst, `extension MergeDecisionLeak on RedactedMergeDecision` adding a plaintext getter and a serializer to a gated class **from outside its body**. | All five declaration kinds are walked — and, more to the point, anything else fails. | Killed, 14 violations across the four constructs. |
| **N4** | A `part of 'sync_merge_models.dart'` file was invisible three times over: not a registry member, not in the registered file's AST, and not caught by an import walker that filtered only `Import`/`Export`. | **Refusal, not resolution** — see below. | Killed. |
| **N5** | Registering into bucket 2 exempted a file from the field rules, and the importer check matched the literal string `merge_field_display.dart`, so a *second* transient file had no import restriction at all. | Importer targets derive from the bucket; the bucket is asserted to be a closed singleton. | Killed on four assertions at once. |
| **N6** | Exemptions were bare identifiers, leaving four names globally free: a new file declaring a class called exactly `MergePreview` was invisible to completeness. | Exemptions are `(identifier, owning file)` pairs. | Killed. |
| **N7** | The layering test judged a registered file's imports but never its location, so a `presentation/` file registered as a merge contract file passed. | Every registered file must live under `domain/`. | Killed on two assertions. |
| **F5 residual** | The doc comment on `token` still read "Safe to log, persist and compare: it is random", contradicting the class doc 30 lines above. | Rewritten to say the safety is conditional on T302a's minting. | Documented. |

**Why `part` is refused rather than resolved.** Resolving would mean parsing the
part, attributing its declarations to the parent and judging them — which needs
a second membership mechanism (part files are not registry entries) and leaves
the import walker still blind to them. Refusal is one rule, it is total, and the
module has no use for parts. `export` is refused for the same reason: it
republishes unjudged declarations through a registered file.

**Proof that the fix is structural, not another enumeration.** A probe was
written against a construct the judge has *no rule for* and whose content is
deliberately harmless — `mixin _Harmless {}` plus
`class MergeAliased = Object with _Harmless;`, containing no `String`, no
secret-bearing name and no serializer. It fails, with
`declares an unhandled top-level construct (ClassTypeAliasImpl)`. Nothing about
that alias is a leak; it fails purely because it is unrecognised, which is the
property the previous two rounds lacked.

Minor follow-ups tracked, not implemented: **F7** (`withChoice` throws
`ArgumentError` while the port declares `SyncMergeFailure` its only error — the
port comment now states the distinction; the total-variant option stays open),
**F8** (`MergeDatabaseId`'s path heuristic accepts `C:vault.kdb`), **F9**
(`MergeReviewSummary` is the one `ArgumentError.value` not passing
`'<redacted>'`).
