import 'package:get_it/get_it.dart';

import '../data/datasources/biometric_data_source.dart';
import '../data/datasources/database_registry_local_data_source.dart';
import '../data/datasources/database_security_local_data_source.dart';
import '../data/datasources/google_token_data_source.dart';
import '../data/datasources/local_data_source.dart';
import '../data/datasources/secure_data_source.dart';
import '../data/datasources/sync_metadata_data_source.dart';
import '../data/repositories/database_registry_repository_impl.dart';
import '../data/repositories/database_security_repository_impl.dart';
import '../data/repositories/database_session_repository_impl.dart';
import '../data/repositories/database_sync_repository_impl.dart';
import '../data/repositories/shared_preferences_password_generator_settings_repository.dart';
import '../data/repositories/sync_merge_repository_impl.dart';
import '../data/services/apple_autofill_v2_method_channel_client.dart';
import '../data/services/database_file_hash_recorder.dart';
import '../data/services/database_path_mutex.dart';
import '../data/services/database_rename_transaction.dart';
import '../data/services/database_sync_orchestrator.dart';
import '../data/services/database_import_service.dart';
import '../data/services/desktop_oauth_pkce_service.dart';
import '../data/services/legacy_database_registry_migration.dart';
import '../data/services/desktop_browser_autofill_cache.dart';
import '../data/services/desktop_browser_autofill_reveal_bridge_service.dart';
import '../data/services/desktop_browser_pending_generation_service.dart';
import '../data/services/drive_auth_service.dart';
import '../data/services/google_drive_api_service.dart';
import '../data/services/google_oauth_config.dart';
import '../data/services/vault_csv_import_service.dart';
import '../data/services/vault_duplicate_service.dart';
import '../data/services/vault_kdbx_service.dart';
import '../domain/repositories/database_file_repository.dart';
import '../domain/repositories/database_registry_repository.dart';
import '../domain/repositories/database_security_repository.dart';
import '../domain/repositories/database_session_repository.dart';
import '../domain/repositories/database_sync_repository.dart';
import '../domain/repositories/autofill_ports.dart';
import '../domain/repositories/password_generator_settings_repository.dart';
import '../domain/repositories/sync_merge_repository.dart';
import '../domain/services/apple_autofill_v2_payload_mapper.dart';
import '../domain/services/vault_autofill_matcher.dart';

void registerPasswordManagerDataDependencies(GetIt sl) {
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
  sl.registerLazySingleton<PasswordGeneratorSettingsRepository>(
    () => SharedPreferencesPasswordGeneratorSettingsRepository(
      sharedPreferences: sl(),
    ),
  );
  // spec 008 T310 — the merge port's data implementation. Registered only now
  // that the frozen T204 contract and this implementation both compile; the
  // presentation layer depends on the T205 use cases and never on this type.
  sl.registerLazySingleton<SyncMergeRepository>(
    () => SyncMergeRepositoryImpl(
      registryRepository: sl(),
      securityRepository: sl(),
      syncRepository: sl(),
      secureDataSource: sl(),
      localDataSource: sl(),
    ),
  );
  sl.registerLazySingleton<DatabaseSessionRepository>(
    () => DatabaseSessionRepositoryImpl(
      localDataSource: sl(),
      secureDataSource: sl(),
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
  sl.registerLazySingleton<GoogleTokenDataSource>(
    () => GoogleTokenDataSourceImpl(secureStorage: sl()),
  );
  sl.registerLazySingleton<SyncMetadataDataSource>(
    () => SyncMetadataDataSourceImpl(),
  );

  sl.registerLazySingleton(() => VaultAutofillMatcher());
  sl.registerLazySingleton(() => const AppleAutofillV2PayloadMapper());
  sl.registerLazySingleton(() => const DesktopBrowserAutofillMetadataMapper());
  sl.registerLazySingleton(() => DesktopBrowserAutofillCacheStore());
  sl.registerLazySingleton(() => DesktopBrowserPendingGenerationService());
  sl.registerLazySingleton(
    () => DesktopBrowserAutofillRevealBridgeService(
      store: sl(),
      mapper: sl(),
      settingsRepository: sl(),
      passwordGenerator: sl(),
      pendingGeneration: sl(),
    ),
  );
  sl.registerLazySingleton<AppleAutofillV2Client>(
    () => AppleAutofillV2MethodChannelClient(),
  );
  // spec 008 T104/T105: one process-wide instance, shared by every database
  // writer below — a writer holding a private mutex would void the
  // serialization guarantee.
  sl.registerLazySingleton(() => DatabasePathMutex());
  sl.registerLazySingleton(
    () => DatabaseFileHashRecorder(registryRepository: sl()),
  );
  sl.registerLazySingleton(
    () => DatabaseRenameTransaction(mutex: sl(), syncRepository: sl()),
  );
  sl.registerLazySingleton(() => VaultCsvImportService());
  sl.registerLazySingleton(() => VaultDuplicateService());
  sl.registerLazySingleton(
    () => VaultKdbxService(mutex: sl(), fileHashRecorder: sl()),
  );
  sl.registerLazySingleton(
    () => DatabaseImportService(
      validateDatabaseUseCase: sl(),
      mutex: sl(),
      fileHashRecorder: sl(),
    ),
  );
  sl.registerLazySingleton<DatabaseFileRepository>(
    () => sl<DatabaseImportService>(),
  );
  sl.registerLazySingleton(
    () => LegacyDatabaseRegistryMigration(
      sharedPreferences: sl(),
      registryRepository: sl(),
    ),
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
      mutex: sl(),
      fileHashRecorder: sl(),
    ),
  );
}
