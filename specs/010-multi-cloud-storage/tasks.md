# 010 — Tasks

Ordered immediate-slice tasks. Each task names owner, files and verification.
Do not start production refactor before characterization tasks pass.

Spec 013 owns the Google OAuth scope and the remote file selection mechanism. No
task here changes the scope, and no task here guarantees the current file list
survives. If 013 lands first, the tasks below that touch the selection surface
rename what 013 shipped instead of what exists today. Do not restate 013's tasks
in this file.

## Clarification traceability

Every clarification in `spec.md` §Clarifications (session 2026-09-04) has an
owning task, so none of them can land as spec text only:

| Clarification | Owning tasks |
| --- | --- |
| Q1 — per-entry decode with quarantine | T103, T104 |
| Q2 — guard covers only remote I/O and vault writes | T302, T304 |
| Q3 — timeout stays in the orchestrator, wrapped as `CloudStorageException(timeout)` | T301 |
| Q4 — mandatory `403` body inspection, status-first precedence | T203 |
| Q5 — dated version-1 backup before the first v2 rewrite | T104b |

Three product decisions raised by those clarifications are open and recorded in
`.specify/state/010/round2/questions.json`. They are **not blocking**: the tasks
below implement the proposed default and name the affected acceptance line as
`[depends on Q6/Q7/Q8]`. Answering a question differently rewrites that line
only.

- **Q6 (E2)** — which component owns the dated version-1 backup. Default:
  `SyncMetadataDataSourceImpl` copies the sealed file byte-for-byte. Affects
  T104b.
- **Q7 (E7)** — where the non-blocking quarantine diagnostic lives. Default:
  typed state at the data source, republished by the repository, no UI. Affects
  T103.
- **Q8 (E13)** — behavior when the **whole** metadata file is undecodable, as
  opposed to one entry. Default: fail closed without destroying, and block
  mapping writes until the file reads again. Affects T103 and T104, and may be
  reassigned to spec 014, which owns the metadata file.

## Phase 0 — Baseline and coordination

- [ ] **T001 Reconcile active spec 008** — owner: `senior-flutter-dev`  
  Files: `specs/008-per-field-conflict-resolution/{spec,plan,tasks}.md`, current
  orchestrator/mapping/DI/mutex changes.  
  Acceptance: implementation base includes latest shared singleton mutex and any
  landed safe-writer work; no 010 branch forks those invariants.  
  Verify: inspect diff/history; run current writer-routing and model suites.

- [ ] **T001b Fix spec 013 sequencing** — owner: `senior-flutter-dev`  
  Files: `specs/013-google-drive-per-file-access/{spec,tasks}.md`, this file.  
  **Decision (2026-08-28): 010 lands first in production; 013 rebases onto the
  neutral models.** 013's Gate 0-A spike runs in parallel on its own
  non-production branch, since it depends on nothing in 010 and blocks everything
  else in 013. The order is forced by 013's external dependencies — a live site,
  a domain verified in Search Console, published consent-screen branding, Gate 0
  runs on a physical Android device, a physical iPhone and real macOS, and a
  Chrome Web Store re-approval — none of which any amount of engineering
  compresses. 010 is pure Dart, unblocked today, and blocking it on that calendar
  buys nothing. The cost of this order is bounded and known: `RemoteFileSelectionData`
  and the characterization of the `files.list` path are work 013 later deletes.
  The reverse order costs more, because 010's whole inventory and baseline would
  be rewritten against a surface that does not exist yet.
  Consequences for this file: T105, T404 and T603 rename and compare against the
  **current in-app list**, which is the surface that exists while 010 lands. 013
  then replaces that implementation behind the port and re-runs
  `remote_file_picker_test.dart` and `sync_status_test.dart`.
  This task changes no 013 task and adds no scope change here.  
  Verify: order recorded; the selection-surface tasks name which surface they
  target; selection suites listed in the rebase step.

- [ ] **T001c Reconcile landed spec 014** — owner: `senior-flutter-dev`  
  Files: `specs/014-managed-storage-hardening/tasks.md`,
  `lib/features/password_manager/data/datasources/{sync_metadata_data_source,metadata_cipher}.dart`,
  `lib/features/password_manager/domain/models/database_sync_mapping.dart`.  
  Spec 014 has already landed almost entirely and it moved the ground under
  every mapping/metadata task in this file. Confirm and record its current
  state, then correct any 010 wording that assumes the pre-014 world as the task
  that touches it lands.  
  Acceptance: four post-014 facts are confirmed against the code and written
  into the plan's dependency gate 6 —
  (a) `sync_mappings.json` is encrypted at rest via `EncryptedMetadataStore`
  (AES-256-GCM), so "inspect the metadata" and "restore the backup" both mean
  ciphertext and both depend on the secure-store metadata key surviving;
  (b) metadata writes already use atomic temp-write + rename, so 010 adds no
  second durability mechanism;
  (c) mappings are keyed by **database identifier**, not by path
  (`getMapping(String databaseId)`), so `databasePath` is location data and any
  010 text treating it as the lookup key is stale;
  (d) an absent key or tampered ciphertext currently reads as *empty*, which is
  indistinguishable from legitimately empty — the exact ambiguity `[depends on
  Q8]` asks about.  
  Verify: read 014's `tasks.md` at implementation time rather than trusting this
  snapshot; run the metadata data source suite before any 010 edit.

- [ ] **T002 Characterize sync algorithm before edits** — owner:
  `senior-flutter-dev`  
  Files: `test/features/password_manager/data/services/database_sync_orchestrator_test.dart`,
  `edit_vs_sync_lost_update_test.dart`, `database_writer_lock_routing_test.dart`.  
  Acceptance: tests pin first baseline, no-change, local-only, remote-only,
  conflict/cancel/keep-local/use-remote, checksum-download fallback, timeout and
  lock release. The timeout case pins the current **failure type** (a bare
  `TimeoutException`) as well as its duration and placement, so T301's
  normalization to `CloudStorageException(timeout)` shows up as exactly one
  intended assertion edit rather than as a silent behavior change.  
  Verify: targeted tests green against unmodified production code.

- [ ] **T003 Characterize Google adapter inputs/outputs** — owner:
  `senior-flutter-dev`  
  Files: `test/features/password_manager/data/services/google_drive_api_service_test.dart`,
  auth service tests if present.  
  Acceptance: account fallback, list/search, pagination, metadata, create, update,
  download and token refresh are pinned. Static UI copy is pinned separately from
  dynamic provider-derived error detail.  
  Verify: targeted Google service tests green; no live account needed.

- [ ] **T004 Add architecture guard (green from the first commit)** — owner:
  `senior-flutter-dev`  
  Files: new
  `test/features/password_manager/data/architecture/cloud_storage_provider_architecture_test.dart`.  
  Acceptance: the guard lands **green against unmodified production code**. It
  asserts today's baseline plus the explicit allowlist, so it fails only on drift.
  Constitution IX forbids committing a red suite, so no assertion describing the
  post-refactor target may be committed in a failing state: each target assertion
  is written **disabled** here and enabled by the task that makes it true.
  Enabling an assertion is part of that task's diff, never a separate commit.
  Complete disabled-assertion list and its owner:

  | Disabled assertion | Enabled by |
  | --- | --- |
  | orchestrator and domain are Google/Drive free | T301 |
  | no bare `TimeoutException` is thrown or propagated out of `data/` | T301 |
  | one provider port, one production implementation, no registry/factory/map | T501 |
  | no provider port injected into presentation | T502 |
  | full legacy-identifier allowlist | T601b |
  
  Verify: `flutter test <this file>` green on the untouched baseline; every
  disabled assertion names the task ID that turns it on; no broad false positives.

- [ ] **T005 Freeze complete legacy-identifier inventory** — owner:
  `senior-flutter-dev`  
  Files: every production/test path listed in `plan.md` M0, including
  `presentation/screens/database_selection_screen.dart`, shared
  `presentation/coordinators/fake_database_ports.dart`, portable-path tests and
  golden suites. Inventory includes `DrivePickerData`, `LoadDriveRemoteFiles`,
  `linkedDriveFileName`, `remoteDriveFiles`, `getDrivePickerData` and
  `presentation/screens/vault/sync_status_test.dart`.  
  Acceptance: the search output is written to
  `specs/010-multi-cloud-storage/manual-qa.md` under a `## Legacy identifier
  inventory` heading (dated, no secrets); every result has a planned migration or
  an explicit justified allowlist entry.  
  Verify: run all `plan.md` M6 legacy/source dependency searches before edits.

## Phase 1 — Generic models and mapping migration

- [ ] **T101 Add provider-neutral remote models** — owner:
  `senior-flutter-dev`  
  Files: new `domain/models/remote_file.dart`,
  `domain/models/storage_account_summary.dart`,
  `domain/models/remote_file_selection_data.dart`; model tests.  
  Acceptance: immutable/equatable remote file, account and selection data preserve
  current fields with no Google SDK/type or credential. `DrivePickerData` is
  replaced by `RemoteFileSelectionData` — acceptance criterion 3 bans the old name
  and this task owns the new one, so the replacement is named here and nowhere
  else. If spec 013 has already deleted that surface (T001b), this model is
  dropped instead of renamed and T404 records that.  
  Verify: model tests and `flutter analyze`.

- [ ] **T102 Rename mapping/conflict vocabulary** — owner:
  `senior-flutter-dev`  
  Files: `domain/models/database_sync_mapping.dart`,
  `domain/models/sync_conflict.dart`,
  `test/features/password_manager/data/portable_path_regression_qa_test.dart`,
  `test/features/password_manager/data/portable_path_serialization_test.dart`,
  direct constructor callers/tests.  
  Acceptance: `providerId`, `remoteFileId`, `remoteFileName`; existing checksums,
  timestamps, auto-sync and error equality unchanged.  
  Verify: constructor/copy/equality tests; source search finds no legacy fields in
  public domain contracts.

- [ ] **T103 Implement exact v1/v2 decode with per-entry quarantine** — owner:
  `senior-flutter-dev`  
  Files: `database_sync_mapping.dart`, `sync_metadata_data_source.dart`, metadata
  tests/fixtures.  
  Acceptance, decode rules: absent provider defaults to `google_drive`; generic
  values win over legacy aliases; legacy fallback works; unknown provider is
  retained but not executable.  
  Acceptance, failure scope (clarification Q1): a missing or invalid required
  identity fails **per entry, not per file**. `getAllMappings` returns every
  entry that decodes. The entry that does not decode is **quarantined**:
  retained verbatim as opaque raw JSON, never interpreted, never executable,
  never matched by a database identifier or remote-identity lookup. The failure
  is surfaced as non-blocking diagnostic state, never thrown as a failure of the
  whole read. Quarantine covers every entry the decoder cannot turn into a
  mapping, **including an entry that is not a JSON object at all** — the current
  silent `.whereType<Map>()` drop is a defect this task closes, not behavior to
  preserve. No entry is silently dropped, no different object is connected, no
  metadata rewrite is triggered by a read and no vault byte is touched.  
  Acceptance, diagnostic surface `[depends on Q7]`: the quarantine state is
  exposed as typed provider-neutral state at the data source (count plus a
  stable safe code) and republished by the repository as a safe value. No UI
  surface and no new user-facing string in this slice. Raw quarantined JSON, the
  metadata path and any remote identity never enter the diagnostic, a log line
  or a `toString`.  
  Acceptance, whole-file failure `[depends on Q8]`: a file that is present but
  not interpretable — invalid JSON, or valid JSON that is not a list — surfaces
  a safe typed metadata error, returns no mappings and **blocks mapping writes**
  until it reads again, so a read that returned empty by accident can never be
  followed by a save that overwrites every mapping with an empty list. The
  post-014 "no key yet" state stays a legitimate empty state in which writes are
  allowed; the two cases are distinguishable, which today they are not.  
  Verify: table-driven migration test for every spec decode rule, plus the six
  fixtures listed in `plan.md` M0; a mixed fixture of several valid mappings and
  one undecodable entry returns every valid mapping and reports exactly one
  quarantined entry.

- [ ] **T104 Write mappings forward to v2, preserving quarantined entries** —
  owner: `senior-flutter-dev`  
  Files: same mapping/data-source files and portable-path tests.  
  Acceptance: successful metadata mutation writes `schemaVersion: 2`, generic
  identity keys and no legacy keys; all non-identity values and portable paths
  survive; reads remain side-effect free.  
  Acceptance, quarantined entries (clarification Q1): the v2 serializer
  re-emits a quarantined entry **unchanged** — it copies the retained raw JSON
  through byte-for-byte, does not upgrade it to v2, does not give it a
  `providerId`, does not reorder it into a decoded shape and does not drop it. A
  write that cannot preserve a quarantined entry **fails instead of losing it**.
  This is what makes "must not silently drop a mapping" enforceable across a
  rewrite rather than only at read time.  
  Verify: decode legacy fixture, mutate, inspect JSON, decode again; assert vault
  fixture checksum/mtime unchanged; round-trip a quarantined entry through
  upsert → read → upsert and assert its bytes are identical to the original;
  assert a serializer that cannot preserve it raises rather than writing a file
  without it.

- [ ] **T104b Back up version-1 metadata before the first v2 rewrite** — owner:
  `senior-flutter-dev`  
  Files: `lib/features/password_manager/data/datasources/sync_metadata_data_source.dart`,
  `test/features/password_manager/data/datasources/sync_metadata_data_source_test.dart`.  
  Clarification Q5 chose a single release plus a preventive backup over a
  two-release reader-then-writer sequence, because the first v2 write is
  irreversible for an older binary and constitution principle VII requires a
  dated copy before an irreversible operation.  
  Acceptance: before the first version-2 rewrite of a given metadata file, a
  dated copy of the existing version-1 file is written alongside it. The copy is
  taken **once**, **before** the mutation, and the mutation does not proceed if
  it cannot be written. It is a copy of the file as it exists on disk — post-014
  that is sealed ciphertext, so this is a byte copy and never a
  decrypt-and-rewrite, and it introduces no plaintext metadata file. It contains
  metadata only: no vault bytes, no credential, no key material. Migration
  writes exactly these two files and never opens, decrypts, copies, renames or
  rewrites a `.kdbx`. A durable marker — the presence of the dated file — stops
  the backup being retaken on every later write.  
  Acceptance, owner `[depends on Q6]`: the default implementation puts this in
  `SyncMetadataDataSourceImpl`, which already owns the path, the directory and
  the atomic write, so no new DI node is added.  
  Acceptance, honest scope: the backup protects against a rolled-back **binary**,
  not against a lost secure-store metadata **key** — restoring it requires that
  key. State that limit in the release note and do not let `spec.md`'s backout
  section imply more.  
  Verify: first v2 write produces the dated file and a second write does not
  produce a second one; a write that cannot create the backup leaves the
  original file byte-identical and performs no mutation; restoring the dated
  copy over the live file decodes back to the original v1 mappings.

- [ ] **T105 Make remote identity a tuple everywhere** — owner:
  `senior-flutter-dev`  
  Files: neutral remote model, mapping/conflict, repository/orchestrator, picker,
  `vault_sync.part.dart`, metadata/picker/coordinator tests and shared fakes.  
  Acceptance: identity and duplicate-link checks always compare
  `(providerId, remoteFileId)`; same opaque ID under two providers is not already
  linked.  
  Verify: mapping migration and picker characterization include same-ID/different-
  provider fixtures.

## Phase 2 — Provider port and Google implementation

- [ ] **T201 Define one provider port and safe errors** — owner:
  `senior-flutter-dev`  
  Files: new `domain/repositories/cloud_storage_provider.dart`,
  `domain/models/cloud_storage_error.dart`; contract tests.  
  Acceptance: one interface contains current auth/account/list/metadata/create/
  update/download operations and stable ID only; no delete, capabilities,
  registry or provider factory.  
  Verify: domain compiles without data imports; architecture guard.

- [ ] **T202 Build Google adapter** — owner: `senior-flutter-dev`  
  Files: new `data/services/google_drive_storage_provider.dart`; change
  `drive_auth_service.dart`, `google_drive_api_service.dart` only as required;
  new adapter tests.  
  Acceptance: adapter composes existing technical services, reports
  `google_drive`, maps neutral models and preserves behavior.  
  Verify: fake auth/API tests for every operation.

- [ ] **T203 Sanitize provider failures** — owner: `senior-flutter-dev`  
  Files: Google adapter/error tests and minimal Google service changes.  
  Acceptance: exact `CloudStorageErrorCode`, safe code and fixed message table in
  `spec.md`; exhaustive Google/transport source mapping including one-refresh
  `401` and deterministic `unknown`; orchestrator-owned `unsupportedProvider` is
  covered by T302 and the orchestrator-owned timeout by T301. Raw SDK exception,
  HTTP body, token-like sentinel, signed URL and stack text never escape or
  persist. No new retry engine. Existing static/unrelated surrounding UI copy
  remains unchanged; unsafe dynamic error detail uses fixed safe text.  
  Acceptance, precedence (clarification Q4) — three rules, none left to
  implementation taste:
  1. an HTTP response is classified by **status code first**;
     `malformedResponse` is reachable **only** from a `2xx` whose payload cannot
     be parsed or is missing a required field. A non-`2xx` keeps its
     status-derived code even when its body is invalid JSON — a `500` with an
     unparsable body is `serverFailure`, never `malformedResponse`;
  2. body inspection is **mandatory on `403`** and is the only case where a body
     affects classification. `rateLimitExceeded`, `userRateLimitExceeded`,
     `dailyLimitExceeded` and `quotaExceeded` map to `rateLimited`; every other
     `403` — absent, unparsable or unrecognized reason — maps to `forbidden`.
     The spec's earlier "may classify" wording is superseded: this is one exact
     expectation, not a permitted choice. The inspected body is discarded
     immediately and is never copied into the exception;
  3. `TimeoutException` in this table means a **transport-level** timeout
     observed inside the adapter, a different code path from the orchestrator's
     per-call timeout; both surface the same `timeout` code and message.  
  Verify: one adversarial test per table row plus unknown, exact strings, sentinel
  absence in exception/string/log/state/persistence, and one case each for the
  three precedence rules — `2xx`-only `malformedResponse`, a `500` with an
  unparsable body, and both `403` rows including an unreadable `403` body.

## Phase 3 — Neutralize data workflow and repository

- [ ] **T301 Inject provider port into orchestrator** — owner:
  `senior-flutter-dev`  
  Files: `data/services/database_sync_orchestrator.dart`, tests/fakes.  
  Acceptance: no Google/Drive import or dependency; provider-neutral timeout name;
  same duration, lock scope, checksum fallback and sync branches.  
  Acceptance, timeout normalization (clarification Q3): the orchestrator **keeps
  ownership** of the per-call timeout and wraps the `TimeoutException` its own
  `.timeout(...)` raises into `CloudStorageException(timeout)` before
  propagating. The duration stays `const Duration(seconds: 30)`, the placement
  stays `_remote` under the writer lock — moving the timeout into the adapter is
  explicitly rejected — no second timeout budget is added, and the failing
  branch, the lock release and the retry behavior are unchanged. Only the
  exception type changes. It matters because this is the last path by which a
  non provider-neutral exception could reach presentation, and without it the
  dynamic error slot has no `safeMessage` for a timeout and spec acceptance
  criterion 10 is unverifiable for that row. Update the stale comment at
  `database_sync_orchestrator.dart` line 39 in the same diff; it currently
  documents the old behavior.  
  Verify: T002 tests unchanged and green except the one timeout assertion, which
  now expects `CloudStorageException(timeout)` with the exact code
  `cloud_storage.timeout` and message `Cloud storage request timed out.`; a test
  asserts the elapsed budget is still 30 s and the lock is released on the
  timeout path; `rg -n 'TimeoutException' lib/features/password_manager` finds
  only wrap sites; enable the T004 assertion that no bare `TimeoutException`
  escapes `data/`; review algorithm-only diff is empty.

- [ ] **T302 Enforce mapping provider identity** — owner:
  `senior-flutter-dev`  
  Files: orchestrator and tests.  
  Acceptance: mapping/provider mismatch fails with safe unsupported-provider error
  before auth, remote call, backup or vault write; exact result
  is `unsupportedProvider` / `cloud_storage.unsupported_provider` /
  `Cloud storage provider is not supported by this build.` Raw provider ID is not
  interpolated; new links use injected provider ID.  
  Acceptance, guard scope (clarification Q2): the guard covers **exactly remote
  I/O and vault writes**. Purely local metadata operations — `removeMapping`,
  `moveMappingPath`, `restoreMappingPathMove` and the auto-sync toggle — are
  **never** blocked by it and must keep working on a mapping whose provider ID
  has no wired adapter. Without this carve-out such a mapping becomes
  unremovable from the app and the only exit is hand-editing an encrypted
  metadata file. Enabling auto-sync on that mapping is therefore permitted; the
  sync run it later triggers still fails closed at the guard. Place the guard on
  the remote/vault path, not on the repository's metadata methods — this also
  resolves the contradiction between dependency rule 7 ("before remote I/O") and
  the older "mapping mutation" wording.  
  Verify: sentinel ID absent from exception/string/log/state/persistence; zero call
  counters and unchanged local/metadata/remote fixtures; on that same mapping,
  remove, path move, move restore and the auto-sync toggle each succeed and
  throw nothing, and enabling auto-sync then running a sync still throws exactly
  `unsupportedProvider`.

- [ ] **T303 Neutralize application repository** — owner:
  `senior-flutter-dev`  
  Files: `domain/repositories/database_sync_repository.dart`,
  `data/repositories/database_sync_repository_impl.dart`, repository fakes/tests.  
  Acceptance: repository remains application boundary; neutral models/method
  names; auth/account through provider, sync through orchestrator.  
  Verify: delegation tests and architecture guard.

- [ ] **T304 Preserve mapping move/remove and auto-sync** — owner:
  `senior-flutter-dev`  
  Files: orchestrator, repository, metadata/rename/background-sync tests.  
  Acceptance: move/remove/toggle semantics and shared rename transaction remain
  unchanged under v2 schema, **including on a mapping with an unsupported
  provider ID** — these are the four operations clarification Q2 exempts from
  the T302 guard, and this task owns proving they still behave identically
  there. Mappings are keyed by database identifier after spec 014 (T001c), so
  move/remove operate on that key and `databasePath` stays location data.  
  Verify: metadata, coordinator and background-sync suites, plus the
  unsupported-provider variant of each of the four operations.

## Phase 4 — Use cases, coordinators and presentation vocabulary

- [ ] **T401 Add meaningful atomic use cases** — owner:
  `senior-flutter-dev`  
  Files: new `domain/usecases/link_database_to_remote_usecase.dart`,
  `sync_database_now_usecase.dart`; use-case tests.  
  Acceptance: link/sync business actions use repository boundary; no pass-through
  use case added for simple getters/toggles.  
  Verify: policy/outcome tests, not constructor-only tests.

- [ ] **T402 Move touched multi-step flow to coordinators** — owner:
  `senior-flutter-dev`  
  Files: `database_session_coordinator.dart`, `vault_session_coordinator.dart`,
  coordinator tests.  
  Acceptance: coordinators sequence connect/list/account/download/import/link and
  vault sync flows; use cases perform atomic link/sync; no provider port enters
  presentation.  
  Verify: coordinator tests cover success/failure/cancellation parity.

- [ ] **T403 Keep VaultBloc thin** — owner: `senior-flutter-dev`  
  Files: `vault_bloc.dart`, `vault_event.dart`, `vault_state.dart`, DI/tests.  
  Acceptance: touched handlers delegate sequencing and emit state; no OAuth,
  provider selection or remote operation chain in BLoC.  
  Verify: background sync, status and error-state tests.

- [ ] **T404 Neutralize touched model names in UI** — owner:
  `senior-flutter-dev`  
  Files: `presentation/screens/database_selection_screen.dart`,
  `vault_sync.part.dart`, `vault_dialogs.part.dart`, `vault_navigation.part.dart`,
  `vault_shell.part.dart`, `widgets/sync/remote_file_row.dart`,
  `widgets/sync/sync_status_hero.dart`, database picker widget/file if needed,
  `test/features/password_manager/presentation/coordinators/fake_database_ports.dart`,
  coordinator/BLoC/navigation/widget tests,
  `test/features/password_manager/presentation/screens/vault/sync_status_test.dart`,
  `test/goldens/database_and_unlock_test.dart`, and
  `test/goldens/sync_health_import_test.dart`.  
  Acceptance: `DrivePickerData`, `LoadDriveRemoteFiles`, `linkedDriveFileName`,
  `remoteDriveFiles` and `getDrivePickerData` are neutralized; intentional Google
  product labels remain narrow. Static/unrelated copy and visual behavior stay
  byte-identical; only unsafe dynamic provider error detail uses fixed safe text;
  no provider picker. The remote file selection surface is exempt from the
  byte-identical guarantee when spec 013 has already replaced it; this task still
  changes only vocabulary there.  
  Verify: string assertions, remote selection and sync status/widget tests; no
  golden changes expected from this task.

## Phase 5 — DI and cleanup

- [ ] **T501 Wire direct Google implementation** — owner:
  `senior-flutter-dev`  
  Files: `di/password_manager_data_di.dart`.  
  Acceptance: one lazy singleton Google adapter, one direct
  `CloudStorageProvider` binding to same instance, injected repository/
  orchestrator, shared existing mutex unchanged; no registry/factory/map.  
  Verify: GetIt resolution test and architecture guard.

- [ ] **T502 Wire use cases/coordinators** — owner: `senior-flutter-dev`  
  Files: `di/password_manager_domain_di.dart`,
  `di/password_manager_presentation_di.dart`.  
  Acceptance: two meaningful use cases registered; coordinators/BLoC resolve;
  provider never injected into presentation.  
  Verify: DI smoke and coordinator/BLoC tests.

- [ ] **T503 Remove obsolete Drive domain models** — owner:
  `senior-flutter-dev`  
  Files: delete `domain/models/drive_remote_file.dart`,
  `domain/models/drive_account_summary.dart`; update all tests/fakes/imports.  
  Acceptance: no compatibility aliases remain; domain/public repository has no
  legacy Drive identity vocabulary. Data-private Google services may retain
  explicit Google names.  
  Verify: source search plus `flutter analyze`.

## Phase 6 — Validation and release gate

- [ ] **T601 Run targeted provider/migration suites** — owner:
  `senior-flutter-dev`  
  Files: tests only as fixes require.  
  Acceptance: architecture, mapping, Google adapter/API, orchestrator, repository
  and use-case suites green.  
  Verify: commands from `plan.md` M6.

- [ ] **T601b Enforce legacy/source allowlist** — owner:
  `senior-flutter-dev`  
  Files: architecture test and all search results.  
  Acceptance: every identifier banned by acceptance criterion 3 in `spec.md` has
  zero code references — that list is maintained in `spec.md` only, so this task
  and `plan.md` M6 reference it instead of restating it and cannot drift from it.
  `driveFileId`/`driveFileName` remain only quoted v1 decoder keys and migration
  fixtures; orchestrator has no direct Google service/auth dependency. Remaining
  Google names are limited to intentional current product UI/action labels and
  data-private Google adapter/technical-service files with focused tests. No loose
  docs allowance applies to production/test search; presentation allowlist names
  each symbol individually and permits no directory/glob/comment exception.
  The `TimeoutException` search from `plan.md` M6 is part of this gate: every
  remaining hit is a wrap site producing `CloudStorageException(timeout)` or a
  test asserting that conversion, and a bare `TimeoutException` propagating out
  of `data/` fails the task.  
  Verify: exact `rg` commands and allowlist from `plan.md` M6.

- [ ] **T602 Run sync safety suites** — owner: `senior-flutter-dev`  
  Files: no production change unless test finds regression.  
  Acceptance: mutex/writer routing, edit-vs-sync, active 008 convergence and
  deletion model suites green; no shared-invariant regression.  
  Verify: commands from `plan.md` M6.

- [ ] **T603 Run presentation regression** — owner:
  `senior-flutter-dev`  
  Files: coordinator/BLoC/widget tests.  
  Acceptance: static/unrelated copy, remote selection, link, sync status/conflict
  and auto-sync behavior unchanged by this refactor; unsafe dynamic provider error
  detail alone uses exact fixed safe message; no unrelated golden update. Selection
  behavior is compared against whatever spec 013 defines when 013 has landed.  
  Verify: targeted presentation tests.

- [ ] **T604 Full static/test gate and scope guard** — owner:
  `senior-flutter-dev`  
  Files: whole Dart workspace.  
  Acceptance: formatted code, `flutter analyze` clean, full `flutter test` green.
  Acceptance criterion 15 is also enforced here: the branch diff touches no native
  platform directory and nothing outside Dart implementation, tests and this
  spec's documentation.  
  Verify: exact commands in `plan.md`, plus

  ```bash
  git diff --name-only origin/main... \
    | grep -E '^(android|ios|macos|windows|linux|web|desktop)/' && exit 1 || true
  ```

  (zero matches required).

- [ ] **T605 Manual Google smoke** — owner: `senior-flutter-dev`  
  Files: `specs/010-multi-cloud-storage/manual-qa.md` under a `## Five-platform
  Google smoke` heading; no secrets recorded.  
  Acceptance: all ten manual steps in `spec.md` are independently recorded for
  Android, iOS, macOS, Windows and Linux. Each platform is
  `pass|fail|not-run`; `not-run` has approver/date/reason waiver. Mobile Google
  Sign-In and desktop OAuth PKCE paths are distinguished; no host inference.
  Task closes only with no `fail` rows and approved waiver for every `not-run`.
  Metadata inspection is redacted and remote remains one externally openable
  `.kdbx`.  
  Acceptance, the two steps the clarifications changed:
  - **step 8** additionally verifies the dated version-1 copy that T104b writes:
    it is present, it is a different file from the live one, and restoring it
    over the live file makes the app decode the original mappings again. A row
    that records the write-forward but not the backup does not satisfy step 8;
  - **step 9** requires decrypting through the app's own read path on the test
    device, because after spec 014 the metadata file is sealed ciphertext and a
    hex dump of it proves nothing. Record only the redacted result — never the
    ciphertext, the key, an account, a path or an object ID.  
  Verify: five dated platform rows without token, account, path or object ID.

## Deferred — not part of immediate definition of done

These are **not tasks**. They are deliberately written without checkboxes: a
`- [ ]` line at column 0 is counted by `tool/sync_spec_project.sh` as an open
task, which would make this spec permanently un-`Done` on Projects #2 even after
the entire immediate slice lands. Each item below becomes a real task in a future
spec, not here.

  - **D001 Select and spike second provider** — requires separate product
    decision and live-service evidence.
  - **D002 Implement second adapter** — after D001.
  - **D003 Add provider resolver/registry** — after two production
    implementations require selection.
  - **D004 Add provider picker/safety-category UI** — requires product copy,
    accessibility and golden scope. Category must use spec 010's pure capability
    derivation, condition-first exact copy and no adapter override.
  - **D005 Add provider switch/migration** — must verify read-back before
    dropping old mapping.
  - **D006 Implement capability evidence enforcement** — before any future
    adapter/capability ships, add exact evidence schema/artifacts, live
    counter-probes, single-file interrupted-write proof and structural test from
    `spec.md`. Negative/missing/inconclusive evidence means absent; artifacts
    contain no credentials, account/object IDs, paths, tokens, URLs or vault
    bytes; present declarations use `VerifiedCapability`, never booleans.

Nothing above blocks T605 or immediate spec completion.
