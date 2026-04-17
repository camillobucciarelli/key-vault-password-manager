import 'package:get_it/get_it.dart';

import '../data/datasources/biometric_data_source.dart';
import '../data/datasources/database_registry_local_data_source.dart';
import '../data/datasources/database_security_local_data_source.dart';
import '../data/datasources/google_token_data_source.dart';
import '../data/datasources/ios_autofill_data_source.dart';
import '../data/datasources/local_data_source.dart';
import '../data/datasources/secure_data_source.dart';
import '../data/datasources/sync_metadata_data_source.dart';
import '../data/repositories/database_registry_repository_impl.dart';
import '../data/repositories/database_repository_impl.dart';
import '../data/repositories/database_security_repository_impl.dart';
import '../data/repositories/database_sync_repository_impl.dart';
import '../data/services/android_autofill_coordinator.dart';
import '../data/services/database_sync_orchestrator.dart';
import '../data/services/database_import_service.dart';
import '../data/services/desktop_autofill_bridge_service.dart';
import '../data/services/desktop_oauth_pkce_service.dart';
import '../data/services/drive_auth_service.dart';
import '../data/services/google_drive_api_service.dart';
import '../data/services/google_oauth_config.dart';
import '../data/services/ios_autofill_snapshot_coordinator.dart';
import '../data/services/vault_csv_import_service.dart';
import '../data/services/vault_duplicate_service.dart';
import '../data/services/vault_kdbx_service.dart';
import '../domain/repositories/database_registry_repository.dart';
import '../domain/repositories/database_repository.dart';
import '../domain/repositories/database_security_repository.dart';
import '../domain/repositories/database_sync_repository.dart';
import '../domain/services/vault_autofill_matcher.dart';

void registerPasswordManagerDataDependencies(GetIt sl) {
  sl.registerLazySingleton<DatabaseRepository>(
    () => DatabaseRepositoryImpl(localDataSource: sl()),
  );
  sl.registerLazySingleton<DatabaseRegistryRepository>(
    () => DatabaseRegistryRepositoryImpl(localDataSource: sl()),
  );
  sl.registerLazySingleton<DatabaseSecurityRepository>(
    () => DatabaseSecurityRepositoryImpl(localDataSource: sl()),
  );
  sl.registerLazySingleton<DatabaseSyncRepository>(
    () => DatabaseSyncRepositoryImpl(
      driveAuthService: sl(),
      databaseSyncOrchestrator: sl(),
    ),
  );

  sl.registerLazySingleton<LocalDataSource>(() => LocalDataSourceImpl());
  sl.registerLazySingleton<DatabaseRegistryLocalDataSource>(
    () => DatabaseRegistryLocalDataSourceImpl(sharedPreferences: sl()),
  );
  sl.registerLazySingleton<DatabaseSecurityLocalDataSource>(
    () => DatabaseSecurityLocalDataSourceImpl(),
  );
  sl.registerLazySingleton<SecureDataSource>(
    () => SecureDataSourceImpl(secureStorage: sl()),
  );
  sl.registerLazySingleton<BiometricDataSource>(
    () => BiometricDataSourceImpl(localAuthentication: sl()),
  );
  sl.registerLazySingleton<IosAutofillDataSource>(
    () => IosAutofillDataSourceImpl(),
  );
  sl.registerLazySingleton<GoogleTokenDataSource>(
    () => GoogleTokenDataSourceImpl(secureStorage: sl()),
  );
  sl.registerLazySingleton<SyncMetadataDataSource>(
    () => SyncMetadataDataSourceImpl(),
  );

  sl.registerLazySingleton(() => VaultAutofillMatcher());
  sl.registerLazySingleton(() => VaultCsvImportService());
  sl.registerLazySingleton(() => VaultDuplicateService());
  sl.registerLazySingleton(() => VaultKdbxService());
  sl.registerLazySingleton(
    () => DatabaseImportService(validateDatabaseUseCase: sl()),
  );
  sl.registerLazySingleton(() => GoogleOAuthConfig.fromEnvironment());
  sl.registerLazySingleton(() => DesktopOAuthPkceService(httpClient: sl()));
  sl.registerLazySingleton(
    () => DriveAuthService(
      config: sl(),
      googleTokenDataSource: sl(),
      desktopOAuthPkceService: sl(),
    ),
  );
  sl.registerLazySingleton(
    () => GoogleDriveApiService(driveAuthService: sl(), httpClient: sl()),
  );
  sl.registerLazySingleton(
    () => DatabaseSyncOrchestrator(
      syncMetadataDataSource: sl(),
      googleDriveApiService: sl(),
    ),
  );

  sl.registerLazySingleton(
    () => AndroidAutofillCoordinator(
      autofillService: sl(),
      getActiveDatabaseUseCase: sl(),
      getSelectedKeyFilePathUseCase: sl(),
      secureDataSource: sl(),
      vaultKdbxService: sl(),
      matcher: sl(),
      passwordGenerator: sl(),
    ),
  );
  sl.registerLazySingleton(
    () => IosAutofillSnapshotCoordinator(
      getActiveDatabaseUseCase: sl(),
      getSelectedKeyFilePathUseCase: sl(),
      secureDataSource: sl(),
      vaultKdbxService: sl(),
      iosAutofillDataSource: sl(),
    ),
  );
  sl.registerLazySingleton(
    () => DesktopAutofillBridgeService(
      getActiveDatabaseUseCase: sl(),
      getSelectedKeyFilePathUseCase: sl(),
      secureDataSource: sl(),
      vaultKdbxService: sl(),
      matcher: sl(),
    ),
  );
}
