# 010 — Implementation plan

## Delivery strategy

Small, behavior-preserving slices. Tests characterize current Google behavior
before production dependencies move. Preserve UI behavior and static/unrelated
copy exactly. Sole intentional copy change: unsafe dynamic provider error details
become spec-fixed provider-neutral safe messages. This authorizes no other copy
change. No big-bang rewrite, provider registry, second provider, provider-picker
UI or sync algorithm change.

Spec 013 is the normative source for the Google OAuth scope and for how a remote
file is selected. This plan neither changes the scope nor preserves the current
remote file list as an invariant; whichever of 010 and 013 lands second rebases
onto the other and re-runs the selection suites. Do not implement 013's tasks
here.

### Clarification-derived invariants (session 2026-09-04)

The five answers in `spec.md` §Clarifications are load-bearing for this plan.
Each one is implemented by a named milestone, so none of them lives only in the
spec:

| Clarification | Decision | Owned by |
| --- | --- | --- |
| Q1 | Mapping decode fails **per entry**; the undecodable entry is quarantined as opaque raw JSON, re-emitted verbatim, and reported as non-blocking diagnostic state | M1 (T103, T104) |
| Q2 | The `providerId` guard covers **only remote I/O and vault writes**; remove, path move, move restore and the auto-sync toggle are never blocked | M3 (T302, T304) |
| Q3 | The per-call timeout **stays in the orchestrator** and is wrapped as `CloudStorageException(timeout)` before it propagates | M3 (T301) |
| Q4 | `403` body inspection is **mandatory**; HTTP status classifies first; `malformedResponse` is reachable only from `2xx` | M2 (T203) |
| Q5 | Single release, plus a **dated backup of the version-1 metadata file** taken before the first version-2 rewrite | M1 (T104b) |

### Open product decisions — assumed defaults in force

Three questions raised by those clarifications are product decisions, not
engineering ones. They are recorded in
`.specify/state/010/round2/questions.json` and are **not** blocking: this plan
proceeds on the proposed default for each, and the sections below that would
change if a different option is chosen are marked inline as
`[depends on Q6]`, `[depends on Q7]` or `[depends on Q8]`.

| Ref | Question | Assumed default while unanswered |
| --- | --- | --- |
| Q6 (finding E2) | Which component owns the dated version-1 backup, and in what form? | `SyncMetadataDataSourceImpl` copies the sealed file byte-for-byte to a dated sibling before the first v2 write; no decryption, no new DI node |
| Q7 (finding E7) | Where does the non-blocking quarantine diagnostic live? | Typed, provider-neutral state at the data source, republished by the repository; no UI surface and no new copy in this slice |
| Q8 (finding E13) | What happens when the **whole** metadata file is undecodable, as opposed to one entry? | Fail closed without destroying: surface a safe typed metadata error, return no mappings, block mapping writes until the file reads again, and keep a dated copy before any repair |

Q8 in particular may turn out to belong to spec 014 rather than here — 014 owns
the metadata file and its encryption. If it does, 010 documents the constraint
and 014 implements it; that reassignment changes M1 and T103/T104 scope but no
other section of this plan.

**Owner agent**: `senior-flutter-dev`  
**Platform agents**: not needed. Involve Android/iOS/macOS/Windows/Linux specialist
only if implementation unexpectedly requires native code; native changes are not
part of this plan.

## Constitution Check

Checked against `.specify/memory/constitution.md` v1.1.2. No gate is violated and
no complexity waiver is needed.

| Principle | Verdict | Evidence |
| --- | --- | --- |
| I — Secrets never leak into the shell | PASS | Spec §Error and security requirements rules 1–8; M2 gate injects a token-like sentinel and asserts absence from `safeCode`/`safeMessage`/`toString`/logs/state/mapping JSON. Neutral models carry no token or SDK object. |
| II — Clean architecture layering holds | PASS | Port in `domain/repositories/`, adapter in `data/services/`, orchestrator behind the port, multi-step flows stay in the two existing coordinators (M4), no new BLoC. |
| III — Design tokens | N/A | No restyle; no colour, type or metric is touched. |
| IV — Pixel fidelity | PASS | No new screen. M4/M6 gate the two existing golden suites as unchanged. |
| V — Accessibility floor | N/A | No layout, contrast, target or animation change. |
| VI — Copy preserved unless a spec marks a change | PASS | Sole authorized change is the dynamic provider-error detail slot, marked in spec §Error and security requirements; all static copy and action labels stay byte-identical. |
| VII — Destructive operations ask first and back up | PASS | This refactor adds no KDBX write path; spec 008 backup/safe-writer and the singleton `DatabasePathMutex` are preserved by gates 2–4. Migration writes exactly two files: `sync_mappings.json` and the dated version-1 copy of it that clarification Q5 requires before the first version-2 rewrite (M1, T104b). That copy is what satisfies this principle for the one irreversible step this spec introduces — the first v2 write, which an older binary cannot read. No user prompt is added, because nothing user-visible is lost and the operation is a metadata rewrite, not a vault mutation. `[depends on Q6]` for which component writes the copy; the obligation itself does not depend on the answer. |
| VIII — Ship the smallest thing | PASS | The port is covered by the explicit exemption for domain ports and platform trust-boundary adapters. No registry, factory, capability interface or second provider (spec §Immediate non-goals); only two use cases, both with transaction value. |
| IX — Verification is local | PASS | M6 runs `flutter analyze` and the full `flutter test` before commit; `pubspec.yaml` is untouched. |

### Phase 0 / Phase 1 artifacts

`research.md` is not generated: `spec.md` carries no `[NEEDS CLARIFICATION]`
marker and no technology choice is open — the provider, the SDKs and the
persistence format are all already in the codebase.

`data-model.md`, `contracts/` and `quickstart.md` are deliberately not generated
either. The constitution requires `data-model.md` only for specs 008 and 009, and
this spec already owns each of those artifacts inline and normatively: entities
and vocabulary in §Domain vocabulary, the port contract in §Provider contract
semantics, the persisted schema and its migration rules in §Persisted mapping
schema and migration, and the error contract in §Error and security requirements.
Validation commands and the manual matrix live in M6 below. Restating any of them
in a side file would create the third copy this spec's acceptance criteria
explicitly forbid, and the copies would drift.

## Dependency and safety gates

1. Reconcile branch with active spec 008 before implementation. Read 008's
   `tasks.md` at that moment for what is closed and what is still moving — do not
   trust a progress snapshot written here, it goes stale. Writer routing,
   collision-safe backup and safe local writer are the parts that matter to 010.
2. Do not edit around or instantiate a private `DatabasePathMutex`. DI must keep
   one process-wide singleton used by every database writer.
3. Do not replace, bypass or duplicate spec 008's collision-safe backup and safe
   writer once those land. This refactor adds no KDBX write path.
4. Keep `DatabaseSyncOrchestrator.syncNow` lock boundary, per-call timeout,
   checksums, backup calls and local/remote decision branches unchanged.
5. If 008 changes orchestrator, mapping, metadata data source or DI concurrently,
   rebase after that slice and rerun its writer-routing/safety suites before 010
   production changes.
6. **Reconcile with spec 014, which has already landed almost entirely.** 014
   changed the ground this plan stands on and every mapping/metadata section
   below assumes its post-014 shape:
   - `sync_mappings.json` is **encrypted at rest** (AES-256-GCM via
     `EncryptedMetadataStore`, spec 014 FR-4). It is not a plaintext file that a
     tester or a rollback script can open. Every "inspect the metadata" and
     "restore the backup" step in this spec means "inspect/restore ciphertext",
     and both work only while the metadata key in the platform secure store
     survives. The dated version-1 backup therefore protects against a rolled
     back **binary**, not against a lost **key** — do not overstate it.
   - Metadata writes already go through an atomic temp-write + rename. 010 adds
     no second durability mechanism.
   - Mappings are keyed by **database identifier**, not by path
     (`getMapping(String databaseId)`, spec 014 FR-6). `databasePath` inside a
     mapping is location data. Any 010 wording or test that treats the path as
     the lookup key is stale and is corrected as it is touched, not left to
     drift further.
   - Read failure modes are already asymmetric and this matters to M1: absent
     key or tampered ciphertext reads as *empty*, which is indistinguishable
     today from *legitimately empty*. See `[depends on Q8]` in M1.
   Verify 014's remaining open task before starting, the same way gate 1 says to
   verify 008: read its `tasks.md` at that moment rather than trusting this
   snapshot.

## Milestones and dependency order

```text
M0 baseline + characterization
 -> M1 neutral models + mapping v2 decoder/writer
 -> M2 provider port + safe errors + Google adapter
 -> M3 orchestrator/repository neutralization
 -> M4 meaningful use cases + coordinator/BLoC vocabulary cleanup
 -> M5 DI switch + deletion of obsolete Drive domain models
 -> M6 targeted/full validation + manual Google smoke
```

Each milestone compiles and tests before the next. Keep compatibility adapters or
temporary deprecated aliases only inside one implementation branch; none remain
at M5.

## M0 — Baseline and architecture characterization

Before changing production code:

- freeze current `DatabaseSyncOrchestrator` outcomes for first baseline,
  no-change, local-only, remote-only, conflict/cancel/keep-local/use-remote,
  metadata-checksum fallback and timeout;
- freeze account fallback, list/query, create/update/download mapping and 401
  token refresh behavior;
- freeze repository/coordinator/BLoC flow behavior and exact static UI strings;
  classify dynamic provider-derived error assertions separately, since only those
  move to fixed safe messages;
- add architecture assertions describing intended dependency target: orchestrator
  must become Google-free, domain must become Drive-model-free, one provider port,
  no registry;
- freeze the orchestrator's current timeout **failure type** as well as its
  duration and placement, so Q3's change from a bare `TimeoutException` to
  `CloudStorageException(timeout)` shows up as exactly one intended assertion
  edit in M3 rather than as a silent behavior change;
- add legacy JSON fixtures before changing mapping decoder. The fixture set is
  not just "v1 vs v2": it must also pin today's three distinct
  whole-file/whole-entry behaviors before any of them is changed, because
  clarification Q1 changes the entry-level one and `[depends on Q8]` may change
  the file-level ones:

  | Fixture | Today's behavior, to be pinned first |
  | --- | --- |
  | entry that is not a JSON object | silently dropped by `.whereType<Map>()` — the defect spec §Backward-compatible decode rule 6 closes |
  | entry missing required remote identity | `fromMap` throws and the **whole read** fails |
  | valid JSON that is not a list | silently returns an empty list |
  | invalid JSON | `FormatException` propagates out of `getAllMappings` |
  | absent metadata key / tampered ciphertext (post-014) | reads as empty, indistinguishable from legitimately empty |
  | mixed file: several valid mappings plus one undecodable entry | today the whole read fails; after Q1 the valid ones must survive |

Likely tests changed/added:

- `test/features/password_manager/data/services/database_sync_orchestrator_test.dart`
- `test/features/password_manager/data/services/google_drive_api_service_test.dart`
- `test/features/password_manager/data/services/database_writer_lock_routing_test.dart`
- `test/features/password_manager/data/services/edit_vs_sync_lost_update_test.dart`
- `test/features/password_manager/data/datasources/sync_metadata_data_source_test.dart`
- `test/features/password_manager/data/architecture/cloud_storage_provider_architecture_test.dart` (new)

Gate: tests fail only on intended dependency/vocabulary work, not behavior.

### Complete known migration inventory

Inventory is search-derived and must be regenerated at implementation time.

Production files known to carry Drive-shaped contract/model/mapping names:

- `lib/features/password_manager/domain/models/database_sync_mapping.dart`
- `lib/features/password_manager/domain/models/sync_conflict.dart`
- `lib/features/password_manager/domain/models/drive_remote_file.dart`
- `lib/features/password_manager/domain/models/drive_account_summary.dart`
- `lib/features/password_manager/domain/repositories/database_sync_repository.dart`
- `lib/features/password_manager/data/datasources/sync_metadata_data_source.dart`
- `lib/features/password_manager/data/repositories/database_sync_repository_impl.dart`
- `lib/features/password_manager/data/services/database_sync_orchestrator.dart`
- `lib/features/password_manager/data/services/google_drive_api_service.dart`
- `lib/features/password_manager/data/services/drive_auth_service.dart`
- `lib/features/password_manager/presentation/bloc/vault/vault_bloc.dart`
- `lib/features/password_manager/presentation/bloc/vault/vault_event.dart`
- `lib/features/password_manager/presentation/bloc/vault/vault_state.dart`
- `lib/features/password_manager/presentation/coordinators/database_session_coordinator.dart`
- `lib/features/password_manager/presentation/coordinators/vault_session_coordinator.dart`
- `lib/features/password_manager/presentation/screens/database_selection_screen.dart`
- `lib/features/password_manager/presentation/screens/vault/vault_sync.part.dart`
- `lib/features/password_manager/presentation/screens/vault/vault_dialogs.part.dart`
- `lib/features/password_manager/presentation/screens/vault/vault_navigation.part.dart`
- `lib/features/password_manager/presentation/screens/vault/vault_shell.part.dart`
- `lib/features/password_manager/presentation/widgets/database/drive_picker_sheet.dart`
- `lib/features/password_manager/presentation/widgets/sync/remote_file_row.dart`
- `lib/features/password_manager/presentation/widgets/sync/sync_status_hero.dart`
- `lib/features/password_manager/di/password_manager_{data,domain,presentation}_di.dart`

Known tests/shared fakes requiring constructor, identity or type migration:

- `test/features/password_manager/data/datasources/sync_metadata_data_source_test.dart`
- `test/features/password_manager/data/portable_path_regression_qa_test.dart`
- `test/features/password_manager/data/portable_path_serialization_test.dart`
- `test/features/password_manager/data/services/database_sync_orchestrator_test.dart`
- `test/features/password_manager/data/services/database_writer_lock_routing_test.dart`
- `test/features/password_manager/data/services/edit_vs_sync_lost_update_test.dart`
- `test/features/password_manager/data/services/google_drive_api_service_test.dart`
- `test/features/password_manager/presentation/coordinators/fake_database_ports.dart`
- `test/features/password_manager/presentation/coordinators/database_session_coordinator_test.dart`
- `test/features/password_manager/presentation/coordinators/vault_session_coordinator_test.dart`
- `test/features/password_manager/presentation/bloc/vault_bloc_background_sync_test.dart`
- `test/features/password_manager/presentation/navigation/vault_surface_migration_matrix_test.dart`
- `test/features/password_manager/presentation/screens/database_selection_unlock_widget_matrix_test.dart`
- `test/features/password_manager/presentation/screens/vault/remote_file_picker_test.dart`
- `test/features/password_manager/presentation/screens/vault/sync_status_test.dart`
- `test/goldens/database_and_unlock_test.dart`
- `test/goldens/sync_health_import_test.dart`

Gate: every listed file is either migrated or explicitly unchanged with reason;
search commands in M6 find no unreviewed caller.

## M1 — Provider-neutral models and mapping v2

### Add

- `lib/features/password_manager/domain/models/remote_file.dart`
- `lib/features/password_manager/domain/models/storage_account_summary.dart`
- `lib/features/password_manager/domain/models/remote_file_selection_data.dart`
  (`RemoteFileSelectionData`, owned by T101, one model per file like its two
  siblings; no extra abstraction layer). Dropped instead of added where spec 013
  has already removed the in-app selection surface.

### Change

- `lib/features/password_manager/domain/models/database_sync_mapping.dart`
- `lib/features/password_manager/domain/models/sync_conflict.dart`
- `lib/features/password_manager/data/datasources/sync_metadata_data_source.dart`
  — this file carries all three of the M1 additions: per-entry quarantine in
  `getAllMappings`, verbatim re-emission in `_saveMappings`, and the dated
  version-1 backup before the first v2 write `[depends on Q6]`. It already owns
  the metadata path, the directory and the atomic write, which is why the
  assumed default puts the backup here rather than in a new node.
- portable-path and metadata tests using mapping constructors/JSON.

Implementation sequence:

1. Introduce neutral models with current fields/`Equatable` behavior.
2. Rename mapping/conflict fields to `remoteFileId`/`remoteFileName`; add stable
   `providerId` and mapping `schemaVersion` semantics.
3. Implement the v1/v2 decoder and the v2-only serializer from spec. Decoding is
   **per entry, not per file** (clarification Q1): the read returns every entry
   that decodes, and an entry that does not decode is quarantined rather than
   dropped or escalated into a whole-file failure. Quarantine has a precise
   meaning that the data model must be able to hold:
   - the entry is retained **verbatim as opaque raw JSON**. It is never
     interpreted, never executable, and never matched by a database identifier
     or remote-identity lookup, so no caller can accidentally act on it;
   - it covers every entry the decoder cannot turn into a mapping, explicitly
     **including an entry that is not a JSON object at all** — the current
     silent `.whereType<Map>()` drop is the defect this closes;
   - the decode failure is surfaced as non-blocking diagnostic state, never as a
     thrown failure of the read `[depends on Q7]`.
4. Preserve portable-path encoding and every existing baseline field.
5. Prove reads do not rewrite metadata and malformed mappings touch no vault.
6. Define every remote identity and duplicate-link check as
   `(providerId, remoteFileId)`. Characterize picker behavior before renaming and
   prove equal opaque IDs from different providers are not duplicates.
7. Serialize quarantined entries back out **unchanged**. The v2 serializer copies
   retained raw JSON through byte-for-byte: not upgraded, not given a
   `providerId`, not reordered, not dropped. A write that cannot preserve a
   quarantined entry **fails instead of losing it** — this is the only way the
   spec's "must not silently drop a mapping" rule is actually enforceable across
   a rewrite.
8. Take the dated version-1 backup required by clarification Q5 before the first
   version-2 rewrite of a given metadata file. Invariants, independent of who
   owns the code `[depends on Q6]`:
   - taken **once**, **before** the mutation, and the mutation does not proceed
     if it cannot be written;
   - it is a copy of the file as it exists on disk — post-014 that is sealed
     ciphertext, so this is a byte copy, not a decrypt-and-rewrite;
   - it contains metadata only: no vault bytes, no credential, no key material;
   - it is a plain restore target for a rolled-back binary, and its usefulness
     ends if the secure-store metadata key is lost. Say that in the release
     note; do not claim more.
9. Whole-file failure is a **separate question from Q1** and is not answered by
   it. Until Q8 is answered, implement the assumed default: a file that is
   present but not interpretable surfaces a safe typed metadata error, returns
   no mappings, and **blocks mapping writes** until it reads again — so that a
   read which returned empty by accident can never be followed by a save that
   overwrites every mapping with an empty list. The post-014 "no key yet"
   state stays a legitimate empty state in which writes are allowed; separating
   those two cases is the whole point `[depends on Q8]`.

No eager migration and no `.kdbx` access.

Gate: the mapping migration matrix passes — mixed aliases, unknown provider,
malformed identity, non-object entry, tuple identity, write-forward, **per-entry
quarantine with verbatim re-emission after a round trip**, **the dated version-1
backup on first rewrite and a restore from it that decodes back to the original
mappings**, and the whole-file failure case above.

## M2 — Port, safe errors and Google adapter

### Add

- `lib/features/password_manager/domain/repositories/cloud_storage_provider.dart`
- `lib/features/password_manager/domain/models/cloud_storage_error.dart`
- `lib/features/password_manager/data/services/google_drive_storage_provider.dart`
- `test/features/password_manager/data/services/google_drive_storage_provider_test.dart`

`CloudStorageProvider` contains current connection/account and object-byte
operations only. `GoogleDriveStorageProvider` composes existing
`DriveAuthService` and `GoogleDriveApiService`.

Change existing Google technical services only where needed to:

- return/map neutral `RemoteFile` values;
- ensure raw Google/HTTP exceptions are caught at adapter boundary;
- preserve static/unrelated copy while replacing only dynamic raw provider detail
  with exact fixed safe messages;
- retain token refresh and query behavior.

Do not create `AuthProvider`, `RemoteObjectStore`, capabilities interface, adapter
factory or provider registry.

Error classification is deterministic per clarification Q4, and the adapter is
structured so that no row of the spec's table is left to implementation taste:

1. An HTTP response is classified by **status code first**. `malformedResponse`
   is reachable only from a `2xx` whose payload cannot be parsed or is missing a
   required field. A non-`2xx` keeps its status-derived code even when its body
   is invalid JSON — a `500` with an unparsable body is `serverFailure`, never
   `malformedResponse`.
2. Body inspection is **mandatory on `403`** and is the only place a body
   affects classification. The four rate-limit reasons map to `rateLimited`;
   every other `403` — absent, unparsable or unrecognized reason — maps to
   `forbidden`. There is no `may` here: the `rateLimited`-from-`403` row is one
   exact expectation. The inspected body is discarded immediately and never
   copied into the exception.
3. `TimeoutException` in the adapter's table means a **transport-level** timeout
   observed inside the adapter. The orchestrator's own per-call timeout is a
   different code path with the same outcome (M3, Q3); both surface the same
   `timeout` code and message.

Gate: contract/adapter tests pass; token-like sentinel in a fake raw failure never
appears in surfaced error, loggable model or serialized mapping. Tests cover every
Google/transport mapping row, exact safe code/message, one-refresh `401` behavior
and deterministic `unknown`, plus the three precedence rules above as their own
cases: `2xx`-only `malformedResponse`, a `500` with an unparsable body, and both
`403` rows. M3 covers orchestrator-owned `unsupportedProvider` and the
orchestrator-owned timeout. No retry engine is added.

## M3 — Orchestrator and repository neutralization

### Change

- `lib/features/password_manager/data/services/database_sync_orchestrator.dart`
- `lib/features/password_manager/data/repositories/database_sync_repository_impl.dart`
- `lib/features/password_manager/domain/repositories/database_sync_repository.dart`
- related orchestrator/repository fakes and tests.

Steps:

1. Replace orchestrator `GoogleDriveApiService` constructor dependency with
   `CloudStorageProvider`; rename `driveCallTimeout`/`_remote` comments and fields
   provider-neutrally without changing value or timeout placement. Per
   clarification Q3 the orchestrator **keeps ownership of the timeout** and
   wraps the `TimeoutException` its own `.timeout(...)` raises into
   `CloudStorageException(timeout)` before propagating. This is a normalization
   of the exception type only:
   - the duration (`const Duration(seconds: 30)`) is unchanged;
   - the placement — `_remote`, under the writer lock — is unchanged, so option
     "move the timeout into the adapter" is explicitly rejected;
   - no second timeout budget is introduced;
   - the failing branch, the lock release and the retry behavior are unchanged.
   The reason this is not cosmetic: it is the last path by which a non
   provider-neutral exception could cross the data boundary into presentation,
   and without it the UI's dynamic error slot has no `safeMessage` to show for a
   timeout and spec acceptance criterion 10 is unverifiable for that row. The
   in-source comment at `database_sync_orchestrator.dart` line 39 currently
   documents the old behavior and is updated with the code.
2. Replace every mapping/conflict Drive field with generic field.
3. Guard provider ID before any provider/local write. Current sole accepted ID
   comes from injected provider instance, not a switch statement. Mismatch throws
   exact `unsupportedProvider` fixed code/message, never interpolates raw ID and
   performs no auth, provider call, backup, metadata mutation or vault write.
   Per clarification Q2 the guard's scope is **exactly remote I/O and vault
   writes**, and this is a carve-out that must be implemented deliberately
   rather than falling out of where the guard happens to sit: `removeMapping`,
   `moveMappingPath`, `restoreMappingPathMove` and the auto-sync toggle are
   purely local metadata operations and are **never** blocked by it. A mapping
   whose provider ID has no wired adapter therefore always remains removable and
   movable from the UI — otherwise the app offers no exit short of hand-editing
   an encrypted metadata file. Enabling auto-sync on such a mapping is likewise
   permitted; the sync run it later triggers still fails closed at the guard.
   Place the guard on the remote/vault path, not on the repository's metadata
   methods.
4. Route metadata/list/create/update/download through provider port.
5. Keep sync decision code structurally unchanged; review this diff separately
   from model renames.
6. Make repository implementation delegate auth/account to provider and workflow
   operations to orchestrator while preserving `DatabaseSyncRepository` as
   application boundary.

Gate: behavior characterization, edit-vs-sync and writer-lock suites green. Diff
shows no changed conflict/checksum branch. Two assertions change intentionally
and are the only expected diff in the M0 baseline: the timeout branch now
expects `CloudStorageException(timeout)` instead of a bare `TimeoutException`
(step 1), and the unsupported-provider case asserts that remove, path move, move
restore and the auto-sync toggle still succeed on the same mapping that fails
remote I/O (step 3). No bare `TimeoutException` escapes the data layer.

## M4 — Use cases, coordinators and touched presentation names

### Add only meaningful use cases

- `lib/features/password_manager/domain/usecases/link_database_to_remote_usecase.dart`
- `lib/features/password_manager/domain/usecases/sync_database_now_usecase.dart`

These actions have business policy/transaction value. Do not add one-line use
cases for `isConnected`, list, account display or simple mapping reads solely for
symmetry.

### Change

- `lib/features/password_manager/presentation/coordinators/database_session_coordinator.dart`
- `lib/features/password_manager/presentation/coordinators/vault_session_coordinator.dart`
- `lib/features/password_manager/presentation/bloc/vault/vault_bloc.dart`
- `vault_event.dart`, `vault_state.dart`
- `lib/features/password_manager/presentation/screens/vault/vault_sync.part.dart`
- `lib/features/password_manager/presentation/screens/vault/vault_dialogs.part.dart`
- `lib/features/password_manager/presentation/screens/database_selection_screen.dart`
- `lib/features/password_manager/presentation/screens/vault/vault_navigation.part.dart`
- `lib/features/password_manager/presentation/screens/vault/vault_shell.part.dart`
- `lib/features/password_manager/presentation/widgets/sync/remote_file_row.dart`
- `lib/features/password_manager/presentation/widgets/sync/sync_status_hero.dart`
- `lib/features/password_manager/presentation/widgets/database/drive_picker_sheet.dart`
  (retain filename because this remains Google Drive UI; change only its imported
  data types; literal Google UI copy stays unchanged)
- coordinator/BLoC/widget tests and shared fakes.

Flow rules:

- `DatabaseSessionCoordinator` continues multi-step connect/list/download/import/
  link flow and calls link use case for atomic link.
- `VaultSessionCoordinator` owns touched multi-step vault sync sequencing and
  calls link/sync use cases where applicable.
- `VaultBloc` remains state/event translation. It receives no provider port and
  contains no provider selection/auth sequencing.
- Rename internal events/state from Drive to remote/cloud only where they carry
  provider-neutral data. Keep explicit product actions such as “Connect Google
  Drive” where they represent current UI copy/product choice.

Gate: no behavior/golden change; coordinator and background-sync tests pass.
Picker tests compare `(providerId, remoteFileId)`, including same opaque ID under
different providers. Existing unsafe dynamic error detail is normalized only as
specified; all surrounding copy remains exact.

## M5 — DI and cleanup

### Change

- `lib/features/password_manager/di/password_manager_data_di.dart`
- `lib/features/password_manager/di/password_manager_domain_di.dart`
- `lib/features/password_manager/di/password_manager_presentation_di.dart`

DI wiring:

```text
DriveAuthService --------------------+
                                      -> GoogleDriveStorageProvider
GoogleDriveApiService ---------------+          |
                                                 v
                                      CloudStorageProvider
                                         |              |
                                         v              v
                              DatabaseSyncRepositoryImpl DatabaseSyncOrchestrator
```

- register Google auth/API technical services as today;
- register one lazy singleton `GoogleDriveStorageProvider`;
- bind one lazy singleton `CloudStorageProvider` to that same instance;
- inject port into repository/orchestrator;
- keep one existing `DatabasePathMutex` singleton;
- register only two meaningful domain use cases;
- inject existing coordinators/BLoC, never provider directly into presentation.

Delete after all callers migrate:

- `lib/features/password_manager/domain/models/drive_remote_file.dart`
- `lib/features/password_manager/domain/models/drive_account_summary.dart`

Do not rename data-private Google token/OAuth files merely for cosmetics. Rename
`DriveAuthService` later only if needed to avoid ambiguity; its Google ownership
is already data-private and changing it adds no boundary value.

Gate: GetIt graph resolves; architecture test finds one implementation, no
registry, no provider in presentation.

## M6 — Validation and release evidence

### Targeted commands

```bash
dart format lib/features/password_manager test/features/password_manager
flutter analyze
flutter test test/features/password_manager/data/architecture/cloud_storage_provider_architecture_test.dart
flutter test test/features/password_manager/data/datasources/sync_metadata_data_source_test.dart
flutter test test/features/password_manager/data/services/google_drive_storage_provider_test.dart
flutter test test/features/password_manager/data/services/google_drive_api_service_test.dart
flutter test test/features/password_manager/data/services/database_sync_orchestrator_test.dart
flutter test test/features/password_manager/data/services/database_writer_lock_routing_test.dart
flutter test test/features/password_manager/data/services/edit_vs_sync_lost_update_test.dart
flutter test test/features/password_manager/presentation/coordinators/database_session_coordinator_test.dart
flutter test test/features/password_manager/presentation/coordinators/vault_session_coordinator_test.dart
flutter test test/features/password_manager/presentation/bloc/vault_bloc_background_sync_test.dart
flutter test test/features/password_manager/presentation/screens/vault/remote_file_picker_test.dart
flutter test test/features/password_manager/presentation/screens/vault/sync_status_test.dart
flutter test test/goldens/sync_health_import_test.dart
flutter test test/goldens/database_and_unlock_test.dart
flutter test
```

Also run current spec 008 model/safety suites if their files or shared writer
dependencies changed:

```bash
flutter test test/features/password_manager/data/services/sync_merge_convergence_model_test.dart
flutter test test/features/password_manager/data/services/sync_merge_deletion_convergence_model_test.dart
```

### Legacy/source dependency acceptance search

Run from repository root after migration:

```bash
# identifier list is owned by spec.md acceptance criterion 3; keep this in sync
# with that list only, never with a third copy elsewhere
rg -n 'DriveRemoteFile|DriveAccountSummary|DrivePickerData|LoadDriveRemoteFiles|linkedDriveFileName|remoteDriveFiles|getDrivePickerData|linkDatabaseToDrive' lib test
rg -n 'driveFileId|driveFileName' lib test
rg -n '\b[A-Za-z_][A-Za-z0-9_]*Drive[A-Za-z0-9_]*\b' \
  lib/features/password_manager/presentation \
  test/features/password_manager/presentation test/goldens
rg -n 'GoogleDriveApiService|DriveAuthService' \
  lib/features/password_manager/data/services/database_sync_orchestrator.dart

# Q3: no bare TimeoutException may escape the data layer. Every remaining hit
# must be inside a catch/wrap that produces CloudStorageException(timeout).
rg -n 'TimeoutException' lib/features/password_manager
```

Expected results:

- first command: zero production/test references;
- second command: only quoted version-1 JSON keys in mapping decoder and explicit
  migration fixtures/assertions; no field/getter/parameter usage;
- third command: every result is individually listed in architecture-test
  allowlist as an intentional current Google product action/label; no directory,
  filename glob, comments/docs or generic `*Drive*` allowance;
- fourth command: zero results;
- fifth command: every hit is a `catch`/wrap site that converts to
  `CloudStorageException(timeout)`, or a test asserting that conversion. A bare
  `TimeoutException` thrown or propagated out of `data/` fails this gate;
- intentional Google product labels may remain only where they name current
  Google-only UI/actions (for example `ConnectGoogleDrive`,
  `DisconnectGoogleDrive`, `BackgroundDriveSync`, `LinkCurrentDatabaseToDrive`,
  `UnlinkCurrentDatabaseFromDrive`, Drive picker filename/widget and literal
  “Google Drive” copy);
- Google service/API names may remain only in data-private Google adapter/
  technical-service files and their focused tests;
- serialized `driveFileId`/`driveFileName` literals may remain only in v1 decoder
  and migration fixtures. No general documentation exception exists in this
  production/test gate.

Architecture test enforces this allowlist so inventory drift fails tests rather
than relying on review alone.

### Manual gate

Run the complete `spec.md` matrix independently on Android, iOS, macOS, Windows
and Linux. Record the results in `specs/010-multi-cloud-storage/manual-qa.md` as
`pass|fail|not-run`; every `not-run` requires approved waiver,
date and reason. Mobile Google Sign-In evidence does not qualify desktop PKCE,
and no host qualifies another platform. No native change is expected, so platform
specialists are needed only if native source changes. Release gate permits no
`fail` row; every `not-run` must carry its approved waiver.

Two steps of that matrix depend on the clarifications and need an explicit
procedure, because after spec 014 the metadata file is ciphertext and cannot be
read with a text editor:

- **step 8** — load a legacy mapping without `providerId`, sync it, verify the
  write-forward, **and verify the dated version-1 copy exists next to the
  migrated file**. Verifying the copy means: it is present, it is a different
  file from the live one, and restoring it over the live file makes the app
  decode the original mappings again. `[depends on Q6]` only for the file's name
  and location;
- **step 9** — inspect redacted metadata for schema v2, `google_drive`, generic
  identity keys, no legacy output keys and no credential. This requires
  decrypting through the app's own read path on the test device; a hex dump of
  the sealed file proves nothing. Record only the redacted result — never the
  ciphertext, the key, an account, a path or an object ID.

## Rollout sequencing

- Keep migration reader and v2 writer in **the same release** (clarification Q5).
  The two-release sequence — ship a v2-tolerant reader first, the v2 writer
  later — was considered and rejected: it is the safest ordering in the
  abstract, but this plan's own rule forbids it and it buys nothing once the
  preventive backup below exists.
- Do not release an intermediate build that writes generic fields but lacks
  provider guard or Google adapter.
- Monitor safe error categories, not raw provider text.
- **Backout order, most preferred first:**
  1. restore the dated version-1 metadata copy that the first write-forward left
     behind, then run the rolled-back binary. This is the intended path and the
     reason the copy exists: rollback becomes a metadata restore instead of an
     emergency compatibility patch built under pressure;
  2. if that copy is absent — or if the secure-store metadata key is gone, in
     which case the copy is unreadable anyway — build a rollback binary whose
     reader tolerates v2. This is the fallback, not the plan;
  3. if mapping metadata is unavailable by either route, disable sync and keep
     the local vault rather than guessing Google identity.
- Never mutate vault bytes to downgrade, under any of the three.

## Deferred implementation plan

Second provider, capability declarations, provider resolver/registry, picker,
provider migration and safety-category UI require a new plan revision after a real
provider is selected and spiked. They are not placeholders to scaffold now.
