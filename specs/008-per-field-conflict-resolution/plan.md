# 008 — Implementation plan

## Strategy

Order: feasibility/report -> writer/path safety -> safe domain models/port/use
cases -> full-fidelity data implementation/DI -> coordinator/BLoC -> UI/goldens.
Private test-only adapter spike may precede domain freeze; production repository
implementation may not. No downstream phase starts before upstream gate passes.

Do not call `KdbxFile.merge`; installed `kdbx` 2.4.2 marks it unfinished. Do not
use `VaultSnapshot` as merge write model. Preserve one-sided records and fields
under all choices.

## Current code anchors

| Current path | Current behavior relevant to feature |
| --- | --- |
| `lib/features/password_manager/data/services/vault_kdbx_service.dart` | `_openFile` resolves passed password/key file; `_save` writes target directly. Entry/group/attachment/recycle-bin mutations converge here, except credential transaction uses separate temp/rename/rollback paths. |
| `lib/features/password_manager/data/services/database_sync_orchestrator.dart` | `syncNow` detects conflicts, performs direct local remote-replacement, backup and Drive upload. |
| `lib/features/password_manager/data/services/google_drive_api_service.dart` | Metadata requests `id,name,modifiedTime,md5Checksum`. `updateFile` sends no precondition, and **none is available**: Drive enforces no conditional write (measured, B1). `md5Checksum` is what FR-7 step 5 compares. |
| `lib/features/password_manager/data/services/database_import_service.dart` | Owns import, staging, commit/finalize/rollback, managed replace/move, database create and key-file save. Several rename/write/delete paths. |
| `lib/features/password_manager/presentation/coordinators/database_session_coordinator.dart` | Drives import/create/replace and directly deletes database file in recent-removal path. |
| `lib/features/password_manager/presentation/coordinators/vault_session_coordinator.dart` | `updateDatabaseSettings` changes credentials, renames database old->new, updates metadata and rolls back. `lockVault` clears credentials. |
| `lib/features/password_manager/presentation/screens/database_selection_screen.dart` | Direct database export `File.copy`. Must move behind domain/data port. |
| `lib/features/password_manager/presentation/screens/vault/vault_navigation.part.dart` | Direct current-database export `File.copy`. Must move behind domain/data port. |
| `lib/features/password_manager/data/datasources/secure_data_source.dart` | Data-owned master-password source. Never expose through sync merge port. |
| `lib/features/password_manager/data/datasources/local_data_source.dart` | Cached key-file path fallback for matching active database. |
| `lib/features/password_manager/domain/repositories/database_registry_repository.dart` and `database_security_repository.dart` | Data implementation uses records/profiles to resolve persisted key-file path and database identity. |
| `lib/features/password_manager/domain/models/database_sync_mapping.dart` | Stores current local/remote checksum baseline; needs pending-recovery metadata. A concurrency token is added **only** for a storage adapter declaring `conditionalWrite`; Drive declares none. |
| `lib/features/password_manager/presentation/bloc/vault/vault_bloc.dart` | `_scheduleAutoSync` debounces background sync. Must call coordinator/use cases only and share data mutex transitively. |
| `lib/features/password_manager/di/password_manager_{data,domain,presentation}_di.dart` | Register data implementation, domain use cases, singleton path mutex and coordinator in correct layer. |

## Gate 0 — spike and mandatory report

### KDBX

Generate compact KDBX 3/4 matrices with password-only/password+key-file and all
library-supported fidelity categories. Save/reopen and compare canonical semantic
manifest. Candidate adapter imports one-sided records/fields/attachments and
applies one conflict choice while unrelated manifest stays equal. Tombstones and
root UUID must be inspectable without `KdbxFile.merge`. Spike also proves
pre-diff rejection for nil live UUID, duplicate entry/group UUID, group-entry UUID
collision and cross-side object-kind mismatch.

### Remote concurrency capabilities

**Measure** which optional concurrency capabilities the backend actually offers
— server-enforced conditional write, version history — against the live service,
with a counter-proof that arbitrary headers reach it. A negative measurement is
a valid Gate 0 result, not a blocker: FR-7 requires only `get` + `put`, so an
absent capability lowers the guarantee tier instead of stopping the feature.

Executed 2026-08-15. Result: **Drive enforces no precondition on the upload
path** — `If-Match`, `If-None-Match: *` and `If-Unmodified-Since` all returned
`200` with the remote bytes actually overwritten, while a `Range` probe returned
`206` to exclude a transport explanation. Drive's `versionHistory` was **not**
measured and is therefore declared **absent**; Drive sits in the **Bare** tier.

Still record the distinction between an HTTP conditional rejection and a
transport failure after dispatch: the rule stays correct for a future
`conditionalWrite` adapter, even though Drive can never produce a rejection.

### Convergence cycle

Because the capability measurement came back negative, the safety mechanism is
FR-7's storage-agnostic write-verify-converge cycle. **That cycle is itself a
Gate 0 deliverable (T009)** and is validated as an in-memory model before any
implementation depends on it: bounded convergence, no one-sided loss under
adversarial interleavings, no oscillation on a timestamp tie, termination on a
semantically complete union, sticky user decisions across a re-merge, and an
ambiguous classification for a non-executable verification.

### Filesystem

Gate 0 defines harness/artifact schema and records each target `not-run`, `passed`,
`failed` or `disabled`. Gate 1 executes target artifacts. Artifact injects
interruption/failure before flush, after flush, during replace and after replace;
it verifies target old or full new and backup no-overwrite behavior.

### T008 report

T008 report is
`specs/008-per-field-conflict-resolution/feasibility-report.md`, Gate 0 output and
prerequisite for Phase 1. It contains:

- KDBX read/import/mutate/write/verify support matrix;
- unsupported-data detector;
- measured remote concurrency capabilities, the resulting guarantee tier and
  the apparent-success/rejection/ambiguous outcome rules;
- the convergence-model validation result (T009);
- complete writer inventory below, updated from implementation-time search;
- canonical path/alias identity algorithm;
- per-platform artifact schema, `not-run|passed|failed|disabled` status, artifact
  path when produced and feature flag; Gate 0 may record `not-run` + disabled,
  while Gate 1 must produce `passed` evidence before enabling;
- model changes required by findings.

Gate 0 exits only when **T001–T009** pass. T001–T008 have executed evidence;
T009 is `not-run` and is the only remaining blocker.

## Clean Architecture

```text
vault widgets ------------------------------------------------------+
  |                                                                |
  | transient display only                                         v
  |                                      LoadSyncMergeFieldDisplayUseCase
  v                                                                |
VaultBloc -> SyncMergeCoordinator -> domain command use cases ------+
                                          |
                                          v
                              SyncMergeRepository (domain port)
                                          ^
                                          |
                     SyncMergeRepositoryImpl (data)
                       - resolves credentials
                       - owns private session store
                       - owns KdbxFile/plaintext/UUID/path/tokens
                       - adapter + mutex + writer + Drive + mapping
```

### Domain port/use cases

New domain port:

`lib/features/password_manager/domain/repositories/sync_merge_repository.dart`

Operations use only opaque/redacted domain types:

```text
startReview(databaseId) -> MergeReviewSummary
updateDecision(sessionId, decisionId, choice) -> MergeReviewSummary
commit(sessionId) -> MergeCommitOutcome
cancel(sessionId)
invalidate(databaseId)
recoverPending(databaseId) -> MergeRecoveryOutcome
loadFieldDisplay(sessionId, decisionId) -> MergeFieldDisplay
```

Focused use cases under `domain/usecases/` wrap each port operation. Data
implementation lives in
`data/repositories/sync_merge_repository_impl.dart` and owns
`KdbxMergeAdapter`, private `KdbxMergeSessionStore`, credential resolution,
preconditions, writes, upload and recovery.

`MergeFieldDisplay` contains transient local/remote values and presence for one
visible decision. It has no Equatable/JSON and redacted `toString`. Field widget
invokes its use case directly and disposes value. Coordinator/BLoC/state never
receive it. `decisionId` is a redacted command identity, not a plaintext handle.

### Coordinator boundary

`presentation/coordinators/sync_merge_coordinator.dart` imports domain use cases
only. It owns opaque session ID, redacted decisions and sequencing. It does not:

- import data source/repository implementation/service/KDBX types;
- read password/key-file path or bytes;
- hold path, checksum, Drive token, root/object UUID, plaintext or plaintext
  handles;
- own private KDBX/session document store.

BLoC forwards events to coordinator and emits redacted summaries/outcome codes.
Lock path calls invalidate use case before credential clear; data implementation
decides pre/post-boundary terminal behavior.

## Data-private merge state

Private store key is opaque `sessionId`. Value owns local/remote `KdbxFile`,
semantic manifests, decrypted field/attachment values, UUID maps, credentials,
canonical path, checksums, remote token, generation and commit boundary state.
Store is never Equatable, logged, serialized or returned through port.

Start review resolves credentials entirely in data implementation, checks root
UUID, computes field/object presence and returns only `MergeReviewSummary`.
Commit accepts session ID only, reruns local/remote preconditions under mutex,
applies redacted decisions stored by data layer and writes candidate.

Before any diff/session, adapter indexes all live roots/groups/entries on each
side and rejects as `unsupportedKdbxData`:

- nil UUID;
- duplicate entry UUID;
- duplicate group UUID;
- any group-entry UUID collision (global uniqueness, not per kind/parent);
- same UUID across local/remote with different object kind.

Validation precedes lineage/diff output and logs safe capability code only.
Fixtures/tests cover each failure independently.

## Field presence algorithm

For each common entry/group UUID, compare union of semantic field keys and
attachment names with explicit `isPresent` flags. Empty present value differs from
missing. With no adapter-proven field deletion marker:

```text
present/present equal      -> identical
present/present different  -> decision
present/missing            -> preserve present local automatically
missing/present            -> preserve present remote automatically
missing/missing            -> absent
```

On a conflicting field the default is the newer KDBX modification time. **On a
tie or an unknown timestamp the default comes from a globally deterministic total
order over the candidate values — unsigned lexicographic, greater wins — never
from "prefer local".** A perspective-dependent default makes the merge function
non-commutative, so two devices flip the field back and forth across sync
sessions. The same order fixes the operand order of the deterministic notes
concatenation. The UI still marks the uncertainty and still offers an override;
only the default is fixed.

An explicit user decision is recorded in a session decision ledger keyed by
object UUID plus field key/attachment name, and re-applied ahead of LWW and the
tie-break on every re-merge round.

Shortcut iteration includes only decision records. It cannot choose missing side.
Explicit field deletion marker, if Gate 0 proves one, creates deletion decision;
delete requires explicit choice/policy. Tests cover local-only/remote-only custom
field and attachment within same entry UUID, including empty value/zero bytes.

## Complete database/path writer inventory

Inventory must be rerun before mutex patch; table is current baseline, not excuse
to miss new writers.

| Writer/path | Current operations | Lock requirement |
| --- | --- | --- |
| `data/services/vault_kdbx_service.dart::_save` callers | `createEntry`, `updateEntry`, `mergeEntries`, add/remove attachment, delete/move entry, create/rename/delete/move group, restore entry/group, permanent delete, empty recycle bin | Exclusive canonical database identity |
| `vault_kdbx_service.dart` credential transaction | `changeCredentials`, `beginCredentialChange`, `finalizeCredentialChange`, `rollbackCredentialChange`; temp/backup/failed renames | Exclusive database identity for entire transaction/rollback |
| `data/services/database_sync_orchestrator.dart::syncNow/_backupFile` | local read/checksum, remote replacement, backup, upload/mapping | Exclusive database identity from final read through mapping/recovery persistence |
| `data/services/database_import_service.dart` | `importFromSelection`, `commitStagedDatabase`, `finalizeDatabaseCommit`, `rollbackDatabaseCommit`, `_moveStagedFile`, `_replaceManagedDatabase`, `createDatabase` | Lock target; replacement/rollback lock staged/source and target identities in sorted order where source can be KDBX |
| `presentation/coordinators/database_session_coordinator.dart` | `selectDriveDatabase`, `_commitStagedImport`, `_applyImportedDatabase`, `resolveDuplicateDecision`, `createNewDatabase`, `removeRecentDatabase` file delete | Refactor file mutation behind domain/data port; same target/source locks |
| `presentation/coordinators/vault_session_coordinator.dart::updateDatabaseSettings` | credential write, target existence, old->new rename, metadata/sync mapping move, rollback rename | Atomically acquire old+new identities sorted; hold through metadata commit/rollback |
| `presentation/screens/database_selection_screen.dart::_onExportRecentDatabase` | direct source `File.copy` to chosen KDBX destination | Refactor behind port; shared lock on source, exclusive destination; both exclusive if alias cannot be excluded |
| `presentation/screens/vault/vault_navigation.part.dart::_exportCurrentDatabase` | direct source `File.copy` to chosen KDBX destination | Same as above |
| new merge data repository | backup, target temp/replace, upload recovery | Exclusive database identity |

Related non-database writers are inventoried but not placed under database mutex:
`DatabaseImportService.saveKeyFile`, key-file exports, and
`VaultKdbxService.exportAttachment`. They must reject destination aliasing any
locked database path and use their own safe no-overwrite rules. If destination is
classified KDBX/database path, database mutex applies.

Implementation adds automated source scan/audit test for `File.write*`,
`rename`, `copy`, `delete` under password-manager feature. Every database-path
mutation must route through audited data gateway. Presentation direct file writes
fail architecture test.

## Path identity and multi-path locking

`DatabasePathMutex` is singleton in data DI. `DatabasePathIdentityResolver`:

1. trims/rejects empty/NUL path, makes absolute, lexical-normalizes separators and
   `.`/`..`;
2. resolves symlinks for existing path;
3. for non-existing target, resolves nearest existing parent then appends
   normalized basename;
4. applies filesystem-proven case semantics, not host assumptions;
5. uses platform file identity for hard links when available; otherwise falls
   back to one global database lock on that platform.

Multiple identities are deduplicated, sorted by stable canonical key, then
acquired in that order. Rename always locks old+new, even if apparent alias.

Tests: relative vs absolute, repeated separators, `.`/`..`, symlink source/parent,
case variants on relevant filesystems, hard links where available, nonexistent
target, same alias twice, old/new reversed concurrent rename and source==target.

## Commit protocol

Inside database mutex:

```text
1. data session current/unlocked check
2. local exact-byte checksum recheck
3. remote metadata checksum/token recheck
4. serialize candidate; reopen with original credentials; semantic validation
5. exclusive-create same-directory backup temp
6. choose microsecond timestamp + collision-resistant suffix; no-overwrite finalize
7. flush/fsync/close and verify backup checksum/size
8. write same-directory target temp; flush/fsync/close
9. recheck invalidation/cancel; atomic replace, never delete-first
10. persist pendingUpload record before remote request
11. upload (`put`); a concurrency token is sent only on a `conditionalWrite`
    adapter
12. classify apparent success / certain rejection (CAS adapters only) /
    ambiguous transport outcome
13. **mandatory step-5 read-back**: equal -> finalize; not executable ->
    ambiguous, enter recovery triage; different -> re-anchor the expected base,
    short-circuit on semantic-manifest equality, else re-merge with the sticky
    decision ledger and repeat from step 3, up to a budget of 3 rounds
14. update mapping only when the read-back proved the remote holds the merged
    state
```

Backup naming collision retries; existing backups never overwritten. Freeze-clock
tests use same microsecond plus precreated final candidates.

## Remote outcome/recovery state machine

```text
pendingUpload
  + certain rejection      -> CAS adapters only; refetch -> new conflict/stale
  + apparent success       -> step-5 read-back
        equal              -> finalized
        not executable     -> persisted ambiguous
        different          -> re-anchor base
                              semantic manifests equal -> finalized
                              new unseen conflict      -> back to review
                              else                     -> re-merge, retry (max 3)
                              budget spent             -> unresolved conflict:
                                                          retain merged local +
                                                          dated backup, never
                                                          mark synced
  + transport ambiguity    -> persisted ambiguous

ambiguous/restart recovery under per-database mutex:
  current local checksum != persisted localCommittedChecksum
      -> staleRecoveryLocal; no remote triage/upload/finalization/vault mutation;
         retain backup/evidence; require fresh conflict
  current local checksum == persisted localCommittedChecksum
      -> refetch remote only now
         remote checksum == merged checksum
             -> finalize mapping, clear pending record
         remote checksum == expected old checksum
             -> safely re-enter FR-7 from step 3; the token is re-sent only on a
                conditionalWrite adapter
         otherwise
             -> retain local+backup, clear retry eligibility, start new conflict
```

Pending record persists before dispatch so process death at any point is
recoverable. Restart initialization acquires database mutex and validates local
checksum before remote fetch or any mutation, then checks record before normal
auto-sync. No blind retry and no premature “synced”.

## Concurrency and lock contract

| Interaction | Behavior |
| --- | --- |
| Edit during review | Allowed; commit returns stale local. |
| Auto/manual sync during review | Allowed; changed precondition invalidates review; no modal. |
| Edit/sync during commit | Queued behind same identity lock; rereads mapping after acquire. |
| Two reviews same database | New data session invalidates old opaque session ID. |
| Different path aliases | Same lock identity or platform global fallback. |
| Rename old/new | Both locks sorted; mapping/profile updates stay inside transaction boundary. |
| Cancel/lock before atomic replace | Abort, clean temp best effort, preserve target/remote. |
| Cancel/lock after replace dispatch | Finish pending-upload/recovery bookkeeping; no rollback. |
| Restart after local replace/upload dispatch | Acquire database mutex; validate current local checksum against persisted committed checksum before remote triage/mutation; recover before auto-sync. |

## Per-platform atomicity evidence

Feature flag is platform-specific and defaults off until matching artifact passes.
Gate 0 report rows may remain `not-run`/disabled. Gate 1 runs harness and updates
`feasibility-report.md` to `passed` with artifact metadata or `failed`/disabled.

| Platform | Harness execution | Required artifact | Qualifies only |
| --- | --- | --- | --- |
| Android | `flutter test integration_test/safe_vault_file_writer_test.dart -d <android-device>` using app storage | `build/safety-evidence/android/safe-vault-writer.json` + log | Android |
| iOS | same harness on iOS simulator and release-target physical device before release | `build/safety-evidence/ios/safe-vault-writer.json` + device log | iOS |
| macOS | harness on macOS app sandbox/runtime | `build/safety-evidence/macos/safe-vault-writer.json` | macOS |
| Windows | harness on native Windows CI runner/filesystem | `build/safety-evidence/windows/safe-vault-writer.json` | Windows |
| Linux | harness on native Linux CI runner/filesystem used for package | `build/safety-evidence/linux/safe-vault-writer.json` | Linux |

Artifact records OS/filesystem/runtime, temp/backup paths category, flush support,
replace semantics, injected failure phase, target checksum and backup checksum.
Host unit tests support logic only and cannot substitute target artifact.

## UI verification inventory

Golden cases are exactly 12, using filenames/states/sizes/themes in `spec.md`.
Test defines `const syncMergeGoldenCases` and asserts length 12 before execution.
Layout/semantics cases are exactly 12: review/field/ready × phone/tablet ×
light/dark. Test asserts unique names, length 12, no exception/overflow and screen
semantic roles using exact names from `spec.md`. Dynamic assertions use four
additional exact names from spec. Scale vault is generated in memory.

## Sequence

```text
G0 T001–T009 spike + report + convergence model
 -> G1 writer inventory/path identity/mutex/platform artifacts
 -> G2 frozen safe domain models/port/use cases (compiling, no data impl)
 -> G3 data adapter/repository implementation/presence/lineage + DI
 -> G4 staleness/backup/atomic commit/upload recovery/restart
 -> G5 coordinator/BLoC/lock/redaction
 -> G6 UI/golden table/widget assertions
 -> G7 manual two-client/platform release verification
```

## Planned files

### New

- `specs/008-per-field-conflict-resolution/feasibility-report.md`
- `test/features/password_manager/data/services/sync_merge_convergence_model_test.dart`
  (T009; in-memory model, no `lib/` dependency)
- `lib/features/password_manager/domain/repositories/sync_merge_repository.dart`
- focused `lib/features/password_manager/domain/usecases/*sync_merge*.dart`
- `lib/features/password_manager/domain/models/sync_merge_models.dart`
- `lib/features/password_manager/data/repositories/sync_merge_repository_impl.dart`
- `lib/features/password_manager/data/services/kdbx_merge_adapter.dart`
- `lib/features/password_manager/data/services/database_path_mutex.dart`
- `lib/features/password_manager/data/services/database_path_identity_resolver.dart`
- `lib/features/password_manager/data/services/safe_vault_file_writer.dart`
- `lib/features/password_manager/presentation/coordinators/sync_merge_coordinator.dart`
- vault merge screen parts and focused tests mirroring these paths
- `integration_test/safe_vault_file_writer_test.dart`

### Modified

Current anchors and three password-manager DI files. UI direct KDBX copy/delete
paths move behind domain/data ports; no presentation `dart:io` mutation remains
for database paths.

## Verification commands

```bash
dart format lib/features/password_manager test/features/password_manager integration_test
flutter analyze
flutter test test/features/password_manager/data/services/vault_kdbx_service_test.dart --plain-name "merge feasibility"
flutter test test/features/password_manager/data/services/sync_merge_convergence_model_test.dart
flutter test test/features/password_manager/data/services/database_path_mutex_test.dart
flutter test test/features/password_manager/data/services/database_writer_inventory_test.dart
flutter test test/features/password_manager/domain/usecases/sync_merge_usecases_test.dart
flutter test test/features/password_manager/data/repositories/sync_merge_repository_impl_test.dart
flutter test test/features/password_manager/data/services/database_sync_orchestrator_test.dart
flutter test test/features/password_manager/presentation/coordinators/sync_merge_coordinator_test.dart
flutter test test/features/password_manager/presentation/bloc/vault_redaction_test.dart
flutter test test/features/password_manager/presentation/bloc/vault_bloc_background_sync_test.dart
flutter test test/goldens --plain-name "sync merge golden inventory"
flutter test test/features/password_manager/presentation/widgets/sync_merge_dynamic_test.dart
flutter test integration_test/safe_vault_file_writer_test.dart -d <target-device>
```

Manual: both shortcuts with one-sided records/fields/attachments; record and field
deletions; local/remote stale races; backup/disk failures; edit/auto-sync/lock at
commit boundary; apparent success verified and diverged; semantic-equivalence
short-circuit; retry-budget exhaustion; non-executable read-back; conditional
rejection on a CAS fake adapter only; timeout with applied/not-applied/third
remote state; restart recovery; reopen with password+key file.

## Residual limits

- No common-ancestor three-way merge.
- Unsupported library constructs block merge.
- Exact Dart secret zeroization unavailable.
- Platform remains disabled until its own evidence artifact passes.
- On a backend without `conditionalWrite` a lost update is detected, not
  prevented, and "non-destructive" is **conditional on every writing device
  resynchronizing**. A device that is overwritten and never comes back online
  loses its contribution from the remote permanently and silently. See `spec.md`
  §"Out of scope / residual limits".
