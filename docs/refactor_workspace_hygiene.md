# Refactor Workspace Hygiene

This note isolates refactor-related changes from unrelated workspace changes.

## Refactor scope

Stage only these paths for the database refactor work:

- `docs/database_flows_refactor.md`
- `lib/features/password_manager/data/datasources/database_registry_local_data_source.dart`
- `lib/features/password_manager/data/datasources/database_security_local_data_source.dart`
- `lib/features/password_manager/data/datasources/sync_metadata_data_source.dart`
- `lib/features/password_manager/data/models/`
- `lib/features/password_manager/data/repositories/database_registry_repository_impl.dart`
- `lib/features/password_manager/data/repositories/database_security_repository_impl.dart`
- `lib/features/password_manager/data/repositories/database_sync_repository_impl.dart`
- `lib/features/password_manager/data/services/database_import_service.dart`
- `lib/features/password_manager/data/services/database_sync_orchestrator.dart`
- `lib/features/password_manager/data/services/android_autofill_coordinator.dart`
- `lib/features/password_manager/data/services/desktop_autofill_bridge_service.dart`
- `lib/features/password_manager/data/services/ios_autofill_snapshot_coordinator.dart`
- `lib/features/password_manager/domain/entities/`
- `lib/features/password_manager/domain/models/database_dedup_result.dart`
- `lib/features/password_manager/domain/models/database_import_result.dart`
- `lib/features/password_manager/domain/models/database_sync_mapping.dart`
- `lib/features/password_manager/domain/repositories/database_registry_repository.dart`
- `lib/features/password_manager/domain/repositories/database_security_repository.dart`
- `lib/features/password_manager/domain/repositories/database_sync_repository.dart`
- `lib/features/password_manager/domain/usecases/get_active_database_usecase.dart`
- `lib/features/password_manager/domain/usecases/get_database_security_profile_usecase.dart`
- `lib/features/password_manager/domain/usecases/get_registered_databases_usecase.dart`
- `lib/features/password_manager/domain/usecases/remove_database_record_usecase.dart`
- `lib/features/password_manager/domain/usecases/resolve_database_duplicate_usecase.dart`
- `lib/features/password_manager/domain/usecases/save_database_security_profile_usecase.dart`
- `lib/features/password_manager/domain/usecases/save_selected_database_path_usecase.dart`
- `lib/features/password_manager/domain/usecases/save_selected_key_file_path_usecase.dart`
- `lib/features/password_manager/domain/usecases/set_active_database_usecase.dart`
- `lib/features/password_manager/domain/usecases/set_biometric_protection_enabled_usecase.dart`
- `lib/features/password_manager/domain/usecases/upsert_database_record_usecase.dart`
- `lib/features/password_manager/di/password_manager_data_di.dart`
- `lib/features/password_manager/di/password_manager_domain_di.dart`
- `lib/features/password_manager/di/password_manager_presentation_di.dart`
- `lib/features/password_manager/presentation/bloc/database_selection/`
- `lib/features/password_manager/presentation/bloc/database_unlock/`
- `lib/features/password_manager/presentation/coordinators/`
- `lib/features/password_manager/presentation/screens/database_selection_screen.dart`
- `lib/features/password_manager/presentation/screens/vault/vault_navigation.part.dart`
- `lib/features/password_manager/presentation/screens/vault/vault_shell.part.dart`
- `lib/features/password_manager/presentation/screens/vault_screen.dart`
- `lib/features/password_manager/presentation/widgets/database/`
- `test/features/password_manager/data/datasources/sync_metadata_data_source_test.dart`
- `test/features/password_manager/data/services/database_sync_orchestrator_test.dart`
- `test/features/password_manager/domain/usecases/resolve_database_duplicate_usecase_test.dart`
- `test/features/password_manager/presentation/bloc/database_selection_bloc_test.dart`
- `test/features/password_manager/presentation/bloc/database_unlock_bloc_test.dart`
- `test/features/password_manager/presentation/coordinators/vault_session_coordinator_test.dart`

Also include deletions for removed legacy files:

- `lib/features/password_manager/domain/usecases/get_selected_database_path_usecase.dart`
- `lib/features/password_manager/domain/usecases/get_recent_database_paths_usecase.dart`
- `lib/features/password_manager/domain/usecases/add_recent_database_path_usecase.dart`
- `lib/features/password_manager/domain/usecases/remove_recent_database_path_usecase.dart`
- `lib/features/password_manager/presentation/screens/database_selection_widgets.part.dart`

## Keep out of refactor commit

Do not include unrelated paths unless explicitly desired:

- `.agent/`
- `.lh/`
- `.github/`
- root changes unrelated to password manager flow (for example `.gitignore`)
