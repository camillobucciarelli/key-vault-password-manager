# 010 — Implementation plan

## Delivery strategy

Small, behavior-preserving slices. Tests characterize current Google behavior
before production dependencies move. Preserve UI behavior and static/unrelated
copy exactly. Sole intentional copy change: unsafe dynamic provider error details
become spec-fixed provider-neutral safe messages. This authorizes no other copy
change. No big-bang rewrite, provider registry, second provider, UI picker or sync
algorithm change.

**Owner agent**: `senior-flutter-dev`  
**Platform agents**: not needed. Involve Android/iOS/macOS/Windows/Linux specialist
only if implementation unexpectedly requires native code; native changes are not
part of this plan.

## Dependency and safety gates

1. Reconcile branch with active spec 008 before implementation. Gate 0/T009 and
   deletion T009b are closed; Phase 1 writer work remains active.
2. Do not edit around or instantiate a private `DatabasePathMutex`. DI must keep
   one process-wide singleton used by every database writer.
3. Do not replace, bypass or duplicate spec 008's collision-safe backup and safe
   writer once those land. This refactor adds no KDBX write path.
4. Keep `DatabaseSyncOrchestrator.syncNow` lock boundary, per-call timeout,
   checksums, backup calls and local/remote decision branches unchanged.
5. If 008 changes orchestrator, mapping, metadata data source or DI concurrently,
   rebase after that slice and rerun its writer-routing/safety suites before 010
   production changes.

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
- add legacy JSON fixtures before changing mapping decoder.

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
- colocate `RemoteFilePickerData` with account summary, matching current
  small-model style; do not create an extra abstraction layer.

### Change

- `lib/features/password_manager/domain/models/database_sync_mapping.dart`
- `lib/features/password_manager/domain/models/sync_conflict.dart`
- `lib/features/password_manager/data/datasources/sync_metadata_data_source.dart`
- portable-path and metadata tests using mapping constructors/JSON.

Implementation sequence:

1. Introduce neutral models with current fields/`Equatable` behavior.
2. Rename mapping/conflict fields to `remoteFileId`/`remoteFileName`; add stable
   `providerId` and mapping `schemaVersion` semantics.
3. Implement strict v1/v2 decoder and v2-only serializer from spec.
4. Preserve portable-path encoding and every existing baseline field.
5. Prove reads do not rewrite metadata and malformed mappings touch no vault.
6. Define every remote identity and duplicate-link check as
   `(providerId, remoteFileId)`. Characterize picker behavior before renaming and
   prove equal opaque IDs from different providers are not duplicates.

No eager migration and no `.kdbx` access.

Gate: mapping migration matrix passes, including mixed aliases, unknown provider,
malformed identity, tuple identity and write-forward.

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

Gate: contract/adapter tests pass; token-like sentinel in a fake raw failure never
appears in surfaced error, loggable model or serialized mapping. Tests cover every
Google/transport mapping row, exact safe code/message, one-refresh `401` behavior
and deterministic `unknown`; M3 covers orchestrator-owned `unsupportedProvider`.
No retry engine is added.

## M3 — Orchestrator and repository neutralization

### Change

- `lib/features/password_manager/data/services/database_sync_orchestrator.dart`
- `lib/features/password_manager/data/repositories/database_sync_repository_impl.dart`
- `lib/features/password_manager/domain/repositories/database_sync_repository.dart`
- related orchestrator/repository fakes and tests.

Steps:

1. Replace orchestrator `GoogleDriveApiService` constructor dependency with
   `CloudStorageProvider`; rename `driveCallTimeout`/`_remote` comments and fields
   provider-neutrally without changing value or timeout placement.
2. Replace every mapping/conflict Drive field with generic field.
3. Guard provider ID before any provider/local write. Current sole accepted ID
   comes from injected provider instance, not a switch statement. Mismatch throws
   exact `unsupportedProvider` fixed code/message, never interpolates raw ID and
   performs no auth, provider call, backup, metadata mutation or vault write.
4. Route metadata/list/create/update/download through provider port.
5. Keep sync decision code structurally unchanged; review this diff separately
   from model renames.
6. Make repository implementation delegate auth/account to provider and workflow
   operations to orchestrator while preserving `DatabaseSyncRepository` as
   application boundary.

Gate: behavior characterization, edit-vs-sync and writer-lock suites green. Diff
shows no changed conflict/checksum branch.

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
rg -n 'DriveRemoteFile|DriveAccountSummary|DrivePickerData|LoadDriveRemoteFiles|linkedDriveFileName|remoteDriveFiles|getDrivePickerData|linkDatabaseToDrive' lib test
rg -n 'driveFileId|driveFileName' lib test
rg -n '\b[A-Za-z_][A-Za-z0-9_]*Drive[A-Za-z0-9_]*\b' \
  lib/features/password_manager/presentation \
  test/features/password_manager/presentation test/goldens
rg -n 'GoogleDriveApiService|DriveAuthService' \
  lib/features/password_manager/data/services/database_sync_orchestrator.dart
```

Expected results:

- first command: zero production/test references;
- second command: only quoted version-1 JSON keys in mapping decoder and explicit
  migration fixtures/assertions; no field/getter/parameter usage;
- third command: every result is individually listed in architecture-test
  allowlist as an intentional current Google product action/label; no directory,
  filename glob, comments/docs or generic `*Drive*` allowance;
- fourth command: zero results;
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
and Linux. Record `pass|fail|not-run`; every `not-run` requires approved waiver,
date and reason. Mobile Google Sign-In evidence does not qualify desktop PKCE,
and no host qualifies another platform. No native change is expected, so platform
specialists are needed only if native source changes. Release gate permits no
`fail` row; every `not-run` must carry its approved waiver.

## Rollout sequencing

- Keep migration reader and v2 writer in same release.
- Do not release an intermediate build that writes generic fields but lacks
  provider guard or Google adapter.
- Monitor safe error categories, not raw provider text.
- Backout with v2-compatible reader; never mutate vault bytes to downgrade.

## Deferred implementation plan

Second provider, capability declarations, provider resolver/registry, picker,
provider migration and safety-category UI require a new plan revision after a real
provider is selected and spiked. They are not placeholders to scaffold now.
