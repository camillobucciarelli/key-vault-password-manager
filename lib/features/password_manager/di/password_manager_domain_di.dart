import 'package:get_it/get_it.dart';

import '../domain/services/password_generator_service.dart';
import '../domain/usecases/connect_google_account_usecase.dart';
import '../domain/usecases/get_active_database_usecase.dart';
import '../domain/usecases/disconnect_google_account_usecase.dart';
import '../domain/usecases/get_database_security_profile_usecase.dart';
import '../domain/usecases/get_drive_connection_status_usecase.dart';
import '../domain/usecases/get_registered_databases_usecase.dart';
import '../domain/usecases/get_selected_key_file_path_usecase.dart';
import '../domain/usecases/link_database_to_drive_usecase.dart';
import '../domain/usecases/list_drive_remote_files_usecase.dart';
import '../domain/usecases/remove_database_record_usecase.dart';
import '../domain/usecases/resolve_database_duplicate_usecase.dart';
import '../domain/usecases/save_database_security_profile_usecase.dart';
import '../domain/usecases/save_selected_database_path_usecase.dart';
import '../domain/usecases/save_selected_key_file_path_usecase.dart';
import '../domain/usecases/set_active_database_usecase.dart';
import '../domain/usecases/set_database_auto_sync_usecase.dart';
import '../domain/usecases/sync_database_now_usecase.dart';
import '../domain/usecases/unlock_database_usecase.dart';
import '../domain/usecases/upsert_database_record_usecase.dart';
import '../domain/usecases/validate_database_usecase.dart';

void registerPasswordManagerDomainDependencies(GetIt sl) {
  sl.registerLazySingleton(() => PasswordGeneratorService());
  sl.registerLazySingleton(() => SaveSelectedDatabasePathUseCase(sl()));
  sl.registerLazySingleton(() => GetRegisteredDatabasesUseCase(sl()));
  sl.registerLazySingleton(() => GetActiveDatabaseUseCase(sl()));
  sl.registerLazySingleton(() => SetActiveDatabaseUseCase(sl()));
  sl.registerLazySingleton(() => UpsertDatabaseRecordUseCase(sl()));
  sl.registerLazySingleton(() => RemoveDatabaseRecordUseCase(sl()));
  sl.registerLazySingleton(() => ResolveDatabaseDuplicateUseCase(sl()));
  sl.registerLazySingleton(() => GetDatabaseSecurityProfileUseCase(sl()));
  sl.registerLazySingleton(() => SaveDatabaseSecurityProfileUseCase(sl()));
  sl.registerLazySingleton(() => GetSelectedKeyFilePathUseCase(sl()));
  sl.registerLazySingleton(() => SaveSelectedKeyFilePathUseCase(sl()));
  sl.registerLazySingleton(() => UnlockDatabaseUseCase());
  sl.registerLazySingleton(() => ValidateDatabaseUseCase());
  sl.registerLazySingleton(() => ConnectGoogleAccountUseCase(sl()));
  sl.registerLazySingleton(() => DisconnectGoogleAccountUseCase(sl()));
  sl.registerLazySingleton(() => GetDriveConnectionStatusUseCase(sl()));
  sl.registerLazySingleton(() => LinkDatabaseToDriveUseCase(sl()));
  sl.registerLazySingleton(() => ListDriveRemoteFilesUseCase(sl()));
  sl.registerLazySingleton(() => SyncDatabaseNowUseCase(sl()));
  sl.registerLazySingleton(() => SetDatabaseAutoSyncUseCase(sl()));
}
