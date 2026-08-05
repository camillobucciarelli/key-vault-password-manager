# 008 — Data model

## Freeze rule

Provisional until Gate 0 tasks T001–T008 pass. Production classes must follow
`feasibility-report.md`, not precede it.

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
  Future<MergeReviewSummary> startReview(String databaseId);

  Future<MergeReviewSummary> updateDecision({
    required String sessionId,
    required String decisionId,
    required MergeChoice choice,
  });

  Future<MergeCommitOutcome> commit(String sessionId);
  Future<void> cancel(String sessionId);
  Future<void> invalidate(String databaseId);
  Future<MergeRecoveryOutcome> recoverPending(String databaseId);

  Future<MergeFieldDisplay> loadFieldDisplay({
    required String sessionId,
    required String decisionId,
  });
}
```

Focused domain use cases wrap each method. `SyncMergeCoordinator` depends on
command use cases only. Field widget depends directly on
`LoadSyncMergeFieldDisplayUseCase`; coordinator/BLoC never sees its plaintext
result.

## Domain-safe models

### `MergeReviewSummary`

```dart
final class MergeReviewSummary extends Equatable {
  const MergeReviewSummary({
    required this.sessionId,
    required this.databaseId,
    required this.phase,
    required this.decisions,
    required this.localOnlyRecordCount,
    required this.remoteOnlyRecordCount,
    required this.oneSidedFieldCount,
  });

  final String sessionId; // random opaque ID
  final String databaseId;
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

final class RedactedMergeDecision extends Equatable {
  const RedactedMergeDecision({
    required this.decisionId,
    required this.ordinal,
    required this.kind,
    required this.category,
    required this.presence,
    required this.choice,
    required this.isDefault,
    required this.timestampRelation,
  });

  final String decisionId; // random command identity, not plaintext handle
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

### `MergeFieldDisplay`

Transient plaintext presentation response for one visible decision:

```dart
final class MergeFieldDisplay {
  const MergeFieldDisplay({
    required this.label,
    required this.local,
    required this.remote,
    required this.protected,
  });

  final String label;
  final MergeDisplaySide local;
  final MergeDisplaySide remote;
  final bool protected;

  @override
  String toString() => 'MergeFieldDisplay(<redacted>)';
}

final class MergeDisplaySide {
  const MergeDisplaySide.present(this.value, {this.changedAt})
      : isPresent = true;

  const MergeDisplaySide.missing()
      : isPresent = false,
        value = null,
        changedAt = null;

  final bool isPresent;
  final String? value;
  final DateTime? changedAt;

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

### Outcomes

```dart
enum MergeFailureCode {
  wrongLineage,
  unsupportedKdbxData,
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
  cancelled,
  sessionInvalidated,
  platformDisabled,
}

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

Data-only `DatabasePathIdentity` contains canonical comparison key and optional
platform file identity. It never enters domain/presentation.

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
