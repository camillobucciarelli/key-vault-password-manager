import 'package:get_it/get_it.dart';

import '../domain/usecases/connect_google_account_usecase.dart';
import '../domain/usecases/disconnect_google_account_usecase.dart';
import '../domain/usecases/get_biometric_protection_enabled_usecase.dart';
import '../domain/usecases/get_drive_connection_status_usecase.dart';
import '../domain/usecases/get_selected_database_path_usecase.dart';
import '../domain/usecases/get_selected_key_file_path_usecase.dart';
import '../domain/usecases/link_database_to_drive_usecase.dart';
import '../domain/usecases/list_drive_remote_files_usecase.dart';
import '../domain/usecases/save_selected_database_path_usecase.dart';
import '../domain/usecases/save_selected_key_file_path_usecase.dart';
import '../domain/usecases/set_biometric_protection_enabled_usecase.dart';
import '../domain/usecases/set_database_auto_sync_usecase.dart';
import '../domain/usecases/sync_database_now_usecase.dart';
import '../domain/usecases/unlock_database_usecase.dart';
import '../domain/usecases/validate_database_usecase.dart';

void registerPasswordManagerDomainDependencies(GetIt sl) {
  sl.registerLazySingleton(() => GetSelectedDatabasePathUseCase(sl()));
  sl.registerLazySingleton(() => SaveSelectedDatabasePathUseCase(sl()));
  sl.registerLazySingleton(() => GetSelectedKeyFilePathUseCase(sl()));
  sl.registerLazySingleton(() => SaveSelectedKeyFilePathUseCase(sl()));
  sl.registerLazySingleton(() => GetBiometricProtectionEnabledUseCase(sl()));
  sl.registerLazySingleton(() => SetBiometricProtectionEnabledUseCase(sl()));
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
