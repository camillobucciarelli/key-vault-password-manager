# 010 — Tasks

Ordered immediate-slice tasks. Each task names owner, files and verification.
Do not start production refactor before characterization tasks pass.

Spec 013 owns the Google OAuth scope and the remote file selection mechanism. No
task here changes the scope, and no task here guarantees the current file list
survives. If 013 lands first, the tasks below that touch the selection surface
rename what 013 shipped instead of what exists today. Do not restate 013's tasks
in this file.

## Phase 0 — Baseline and coordination

- [ ] **T001 Reconcile active spec 008** — owner: `senior-flutter-dev`  
  Files: `specs/008-per-field-conflict-resolution/{spec,plan,tasks}.md`, current
  orchestrator/mapping/DI/mutex changes.  
  Acceptance: implementation base includes latest shared singleton mutex and any
  landed safe-writer work; no 010 branch forks those invariants.  
  Verify: inspect diff/history; run current writer-routing and model suites.

- [ ] **T002 Characterize sync algorithm before edits** — owner:
  `senior-flutter-dev`  
  Files: `test/features/password_manager/data/services/database_sync_orchestrator_test.dart`,
  `edit_vs_sync_lost_update_test.dart`, `database_writer_lock_routing_test.dart`.  
  Acceptance: tests pin first baseline, no-change, local-only, remote-only,
  conflict/cancel/keep-local/use-remote, checksum-download fallback, timeout and
  lock release.  
  Verify: targeted tests green against unmodified production code.

- [ ] **T003 Characterize Google adapter inputs/outputs** — owner:
  `senior-flutter-dev`  
  Files: `test/features/password_manager/data/services/google_drive_api_service_test.dart`,
  auth service tests if present.  
  Acceptance: account fallback, list/search, pagination, metadata, create, update,
  download and token refresh are pinned. Static UI copy is pinned separately from
  dynamic provider-derived error detail.  
  Verify: targeted Google service tests green; no live account needed.

- [ ] **T004 Add architecture guard** — owner: `senior-flutter-dev`  
  Files: new
  `test/features/password_manager/data/architecture/cloud_storage_provider_architecture_test.dart`.  
  Acceptance: guard can assert orchestrator/domain Google freedom, one provider
  port/implementation, no registry and no provider injection into presentation;
  expected target assertions may initially fail until later tasks.  
  Verify: baseline mode/current exceptions explicit, no broad false positives.

- [ ] **T005 Freeze complete legacy-identifier inventory** — owner:
  `senior-flutter-dev`  
  Files: every production/test path listed in `plan.md` M0, including
  `presentation/screens/database_selection_screen.dart`, shared
  `presentation/coordinators/fake_database_ports.dart`, portable-path tests and
  golden suites. Inventory includes `DrivePickerData`, `LoadDriveRemoteFiles`,
  `linkedDriveFileName`, `remoteDriveFiles`, `getDrivePickerData` and
  `presentation/screens/vault/sync_status_test.dart`.  
  Acceptance: search output is saved in task evidence; every result has a planned
  migration or explicit justified allowlist entry.  
  Verify: run all `plan.md` M6 legacy/source dependency searches before edits.

## Phase 1 — Generic models and mapping migration

- [ ] **T101 Add provider-neutral remote models** — owner:
  `senior-flutter-dev`  
  Files: new `domain/models/remote_file.dart`,
  `domain/models/storage_account_summary.dart`; model tests.  
  Acceptance: immutable/equatable remote file, account and picker data preserve
  current fields with no Google SDK/type or credential.  
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

- [ ] **T103 Implement exact v1/v2 decode** — owner: `senior-flutter-dev`  
  Files: `database_sync_mapping.dart`, `sync_metadata_data_source.dart`, metadata
  tests/fixtures.  
  Acceptance: absent provider defaults to `google_drive`; generic values win;
  legacy fallback works; unknown provider retained; malformed required identity
  fails closed without rewrite or vault access.  
  Verify: table-driven migration test for every spec decode rule.

- [ ] **T104 Write mappings forward to v2** — owner: `senior-flutter-dev`  
  Files: same mapping/data-source files and portable-path tests.  
  Acceptance: successful metadata mutation writes `schemaVersion: 2`, generic
  identity keys and no legacy keys; all non-identity values and portable paths
  survive; reads remain side-effect free.  
  Verify: decode legacy fixture, mutate, inspect JSON, decode again; assert vault
  fixture checksum/mtime unchanged.

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
  `401`, `403` rate-limit precedence and deterministic `unknown`;
  orchestrator-owned `unsupportedProvider` is covered by T302. Raw SDK exception,
  HTTP body, token-like sentinel, signed URL and stack text never escape or
  persist. No new retry engine. Existing static/unrelated surrounding UI copy
  remains unchanged; unsafe dynamic error detail uses fixed safe text.  
  Verify: one adversarial test per table row plus unknown, exact strings, sentinel
  absence in exception/string/log/state/persistence.

## Phase 3 — Neutralize data workflow and repository

- [ ] **T301 Inject provider port into orchestrator** — owner:
  `senior-flutter-dev`  
  Files: `data/services/database_sync_orchestrator.dart`, tests/fakes.  
  Acceptance: no Google/Drive import or dependency; provider-neutral timeout name;
  same duration, lock scope, checksum fallback and sync branches.  
  Verify: T002 tests unchanged and green; review algorithm-only diff is empty.

- [ ] **T302 Enforce mapping provider identity** — owner:
  `senior-flutter-dev`  
  Files: orchestrator and tests.  
  Acceptance: mapping/provider mismatch fails with safe unsupported-provider error
  before auth, remote call, backup, metadata mutation or local write; exact result
  is `unsupportedProvider` / `cloud_storage.unsupported_provider` /
  `Cloud storage provider is not supported by this build.` Raw provider ID is not
  interpolated; new links use injected provider ID.  
  Verify: sentinel ID absent from exception/string/log/state/persistence; zero call
  counters and unchanged local/metadata/remote fixtures.

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
  unchanged under v2 schema.  
  Verify: metadata, coordinator and background-sync suites.

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
  Acceptance: `DriveRemoteFile`, `DriveAccountSummary`, `DrivePickerData`,
  `LoadDriveRemoteFiles`, `linkedDriveFileName`, `remoteDriveFiles`,
  `getDrivePickerData` and `linkDatabaseToDrive` have zero code references;
  `driveFileId`/`driveFileName` remain only quoted v1 decoder keys and migration
  fixtures; orchestrator has no direct Google service/auth dependency. Remaining
  Google names are limited to intentional current product UI/action labels and
  data-private Google adapter/technical-service files with focused tests. No loose
  docs allowance applies to production/test search; presentation allowlist names
  each symbol individually and permits no directory/glob/comment exception.  
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

- [ ] **T604 Full static/test gate** — owner: `senior-flutter-dev`  
  Files: whole Dart workspace.  
  Acceptance: formatted code, `flutter analyze` clean, full `flutter test` green.  
  Verify: exact commands in `plan.md`.

- [ ] **T605 Manual Google smoke** — owner: `senior-flutter-dev`  
  Files: release evidence only; no secrets recorded.  
  Acceptance: all ten manual steps in `spec.md` are independently recorded for
  Android, iOS, macOS, Windows and Linux. Each platform is
  `pass|fail|not-run`; `not-run` has approver/date/reason waiver. Mobile Google
  Sign-In and desktop OAuth PKCE paths are distinguished; no host inference.
  Task closes only with no `fail` rows and approved waiver for every `not-run`.
  Metadata inspection is redacted and remote remains one externally openable
  `.kdbx`.  
  Verify: five dated platform rows without token, account, path or object ID.

## Deferred — not part of immediate definition of done

- [ ] **D001 Select and spike second provider** — deferred; requires separate
  product decision and live-service evidence.
- [ ] **D002 Implement second adapter** — deferred until D001.
- [ ] **D003 Add provider resolver/registry** — deferred until two production
  implementations require selection.
- [ ] **D004 Add provider picker/safety-category UI** — deferred; requires product
  copy, accessibility and golden scope. Category must use spec 010's pure
  capability derivation, condition-first exact copy and no adapter override.
- [ ] **D005 Add provider switch/migration** — deferred; must verify read-back
  before dropping old mapping.
- [ ] **D006 Implement capability evidence enforcement** — deferred; before any
  future adapter/capability ships, add exact evidence schema/artifacts, live
  counter-probes, single-file interrupted-write proof and structural test from
  `spec.md`. Negative/missing/inconclusive evidence means absent; artifacts
  contain no credentials, account/object IDs, paths, tokens, URLs or vault bytes;
  present declarations use `VerifiedCapability`, never booleans.

Deferred boxes intentionally remain unchecked and do not block T605 or immediate
spec completion.
