# 010 — Manual QA and inventories

## Legacy identifier inventory

Frozen 2026-09-05 on `main` (`3240a5b`) before any 010 production edit — spec
010 T005. Regenerated with the plan.md M6 searches; counts are matching lines
per file. No secrets. Every file below is either migrated by the task named
in the right column or individually allowlisted in
`test/features/password_manager/data/architecture/cloud_storage_provider_architecture_test.dart`.

### Banned contract identifiers and v1 keys

`rg -c 'DriveRemoteFile|DriveAccountSummary|DrivePickerData|LoadDriveRemoteFiles|linkedDriveFileName|remoteDriveFiles|getDrivePickerData|linkDatabaseToDrive|driveFileId|driveFileName' lib test`

| File | Hits | Disposition |
| --- | --- | --- |
| `lib/features/password_manager/data/repositories/database_sync_repository_impl.dart` | 4 | T303 neutral delegation |
| `lib/features/password_manager/data/repositories/sync_merge_repository_impl.dart` | 11 | T202 consume neutral RemoteFile (spec 008 merge writer unchanged) |
| `lib/features/password_manager/data/services/database_sync_orchestrator.dart` | 23 | T301/T302 provider port |
| `lib/features/password_manager/data/services/drive_auth_service.dart` | 4 | T202 return neutral models (data-private Google service stays) |
| `lib/features/password_manager/data/services/google_drive_api_service.dart` | 9 | T202 return neutral models (data-private Google service stays) |
| `lib/features/password_manager/domain/models/database_sync_mapping.dart` | 14 | T102/T103 rename fields, v2 decoder |
| `lib/features/password_manager/domain/models/drive_account_summary.dart` | 7 | T101 add neutral model; T503 delete |
| `lib/features/password_manager/domain/models/drive_remote_file.dart` | 2 | T101 add neutral model; T503 delete |
| `lib/features/password_manager/domain/models/sync_conflict.dart` | 6 | T102/T103 rename fields, v2 decoder |
| `lib/features/password_manager/domain/repositories/database_sync_repository.dart` | 3 | T303 neutral signatures |
| `lib/features/password_manager/presentation/bloc/vault/vault_bloc.dart` | 22 | T404 vocabulary |
| `lib/features/password_manager/presentation/bloc/vault/vault_event.dart` | 3 | T404 vocabulary |
| `lib/features/password_manager/presentation/bloc/vault/vault_state.dart` | 28 | T404 vocabulary |
| `lib/features/password_manager/presentation/coordinators/database_session_coordinator.dart` | 5 | T404 vocabulary |
| `lib/features/password_manager/presentation/screens/database_selection_screen.dart` | 1 | T404 vocabulary |
| `lib/features/password_manager/presentation/screens/vault/vault_shell.part.dart` | 1 | T404 vocabulary |
| `lib/features/password_manager/presentation/screens/vault/vault_sync.part.dart` | 18 | T404 vocabulary |
| `lib/features/password_manager/presentation/widgets/database/drive_picker_sheet.dart` | 5 | T404 vocabulary |
| `lib/features/password_manager/presentation/widgets/sync/remote_file_row.dart` | 2 | T404 vocabulary |
| `lib/features/password_manager/presentation/widgets/sync/sync_status_hero.dart` | 3 | T404 vocabulary |
| `test/features/password_manager/data/architecture/cloud_storage_provider_architecture_test.dart` | 9 | review |
| `test/features/password_manager/data/datasources/encrypted_metadata_test.dart` | 3 | T103/T104 v1 fixtures allowlisted as quoted keys |
| `test/features/password_manager/data/datasources/sync_metadata_data_source_test.dart` | 3 | T103/T104 v1 fixtures allowlisted as quoted keys |
| `test/features/password_manager/data/portable_path_regression_qa_test.dart` | 9 | T103/T104 v1 fixtures allowlisted as quoted keys |
| `test/features/password_manager/data/portable_path_serialization_test.dart` | 5 | T103/T104 v1 fixtures allowlisted as quoted keys |
| `test/features/password_manager/data/repositories/sync_merge_repository_impl_test.dart` | 11 | T301/T202 fakes |
| `test/features/password_manager/data/services/database_sync_orchestrator_test.dart` | 23 | T301/T202 fakes |
| `test/features/password_manager/data/services/database_writer_lock_routing_test.dart` | 9 | T301/T202 fakes |
| `test/features/password_manager/data/services/drive_auth_service_test.dart` | 1 | T301/T202 fakes |
| `test/features/password_manager/data/services/edit_vs_sync_lost_update_test.dart` | 5 | T301/T202 fakes |
| `test/features/password_manager/data/services/google_drive_api_service_test.dart` | 5 | T301/T202 fakes |
| `test/features/password_manager/presentation/bloc/vault_bloc_background_sync_test.dart` | 11 | T404 fakes/assertions |
| `test/features/password_manager/presentation/bloc/vault_bloc_sync_merge_test.dart` | 7 | T404 fakes/assertions |
| `test/features/password_manager/presentation/coordinators/database_session_coordinator_test.dart` | 28 | T404 fakes/assertions |
| `test/features/password_manager/presentation/coordinators/fake_database_ports.dart` | 7 | T404 fakes/assertions |
| `test/features/password_manager/presentation/coordinators/vault_session_coordinator_test.dart` | 4 | T404 fakes/assertions |
| `test/features/password_manager/presentation/navigation/vault_surface_migration_matrix_test.dart` | 1 | T404 fakes/assertions |
| `test/features/password_manager/presentation/screens/database_selection_unlock_widget_matrix_test.dart` | 2 | T404 fakes/assertions |
| `test/features/password_manager/presentation/screens/vault/remote_file_picker_test.dart` | 9 | T404 fakes/assertions |
| `test/features/password_manager/presentation/screens/vault/sync_status_test.dart` | 3 | T404 fakes/assertions |
| `test/features/password_manager/presentation/widgets/database/google_oauth_config_repro_test.dart` | 11 | T404 fakes/assertions |
| `test/features/password_manager/presentation/widgets/sync/remote_file_row_test.dart` | 3 | T404 fakes/assertions |
| `test/features/password_manager/presentation/widgets/sync/sync_merge_screen_test.dart` | 4 | T404 fakes/assertions |
| `test/fixtures/vault_dialogs_002_before.txt` | 1 | T404: v1 dialog copy fixture, quoted placeholder only |
| `test/goldens/database_and_unlock_test.dart` | 3 | T404 fakes/assertions |
| `test/goldens/sync_health_import_test.dart` | 17 | T404 fakes/assertions |

### `*Drive*` identifiers in presentation

`rg -o '\b[A-Za-z_][A-Za-z0-9_]*Drive[A-Za-z0-9_]*\b' lib/features/password_manager/presentation test/features/password_manager/presentation test/goldens | sort | uniq -c`

Renamed by T404 (provider-neutral data): `LoadDriveRemoteFiles`,
`linkedDriveFileName`, `remoteDriveFiles`, `isLoadingRemoteDriveFiles`,
`remoteDriveFilesError`, `remoteDriveFilesReconnectRequired`,
`clearRemoteDriveFilesError`, `getDrivePickerData`, `linkDatabaseToDrive`,
`_onLoadDriveRemoteFiles`, `GoogleDriveApiService` (test import),
`listKdbxFilesInDrive` (test fake).
Everything else is an intentional Google product action/label and is listed by
name in the architecture test allowlist.

| Count | Identifier |
| --- | --- |
| 48 | `isDriveConnected` |
| 46 | `isDriveLinked` |
| 26 | `linkedDriveFileName` |
| 25 | `BackgroundDriveSync` |
| 21 | `isLoadingRemoteDriveFiles` |
| 20 | `remoteDriveFiles` |
| 19 | `remoteDriveFilesError` |
| 16 | `remoteDriveFilesReconnectRequired` |
| 9 | `GoogleDriveReconnectContinuation` |
| 8 | `LoadDriveRemoteFiles` |
| 8 | `linkDatabaseToDrive` |
| 8 | `GoogleDriveReconnectCoordinator` |
| 8 | `ConnectGoogleDrive` |
| 7 | `selectDriveDatabase` |
| 7 | `LinkCurrentDatabaseToDrive` |
| 7 | `GoogleDriveReconnectFailed` |
| 7 | `clearRemoteDriveFilesError` |
| 6 | `showDrivePickerSheet` |
| 6 | `SelectDriveDatabase` |
| 6 | `GoogleDriveReconnectSucceeded` |
| 5 | `UnlinkCurrentDatabaseFromDrive` |
| 5 | `DisconnectGoogleDrive` |
| 5 | `_prepareDriveDuplicate` |
| 5 | `_DrivePickerSheetContent` |
| 4 | `onOpenFromGoogleDrive` |
| 4 | `onOpenFromDrive` |
| 4 | `ExistingDriveLinkResult` |
| 4 | `_onBackgroundDriveSync` |
| 4 | `_emitDriveAuthorizationRequired` |
| 3 | `NewDriveLinkResult` |
| 3 | `getDrivePickerData` |
| 3 | `_requiresDrivePermissionReauth` |
| 3 | `_pickExistingDriveFile` |
| 3 | `_openFromGoogleDrive` |
| 3 | `_DriveEmptyState` |
| 3 | `_buildDriveConnectErrorMessage` |
| 2 | `stageDriveDownload` |
| 2 | `_preloadDriveStateFromLocalMapping` |
| 2 | `_onUnlinkCurrentDatabaseFromDrive` |
| 2 | `_onSelectDriveDatabase` |
| 2 | `_onLoadDriveRemoteFiles` |
| 2 | `_onLinkCurrentDatabaseToDrive` |
| 2 | `_onGoogleDriveReconnectSucceeded` |
| 2 | `_onGoogleDriveReconnectFailed` |
| 2 | `_onDisconnectGoogleDrive` |
| 2 | `_onConnectGoogleDrive` |
| 2 | `_DrivePickerSheetContentState` |
| 2 | `_createNewDriveFile` |
| 1 | `listKdbxFilesInDrive` |
| 1 | `GoogleDriveApiService` |

### Orchestrator Google dependency

`rg -n 'GoogleDriveApiService|DriveAuthService' lib/features/password_manager/data/services/database_sync_orchestrator.dart`

    22:    required GoogleDriveApiService googleDriveApiService,
    51:  final GoogleDriveApiService _googleDriveApiService;

Removed by T301.
