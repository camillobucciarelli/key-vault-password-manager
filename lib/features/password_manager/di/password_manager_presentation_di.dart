import 'package:get_it/get_it.dart';

import '../data/services/android_autofill_coordinator.dart';
import '../data/services/ios_autofill_snapshot_coordinator.dart';
import '../presentation/bloc/database_selection/database_selection_bloc.dart';
import '../presentation/bloc/database_unlock/database_unlock_bloc.dart';
import '../presentation/bloc/vault/vault_bloc.dart';
import '../presentation/coordinators/database_session_coordinator.dart';
import '../presentation/coordinators/vault_session_coordinator.dart';

void registerPasswordManagerPresentationDependencies(GetIt sl) {
  sl.registerLazySingleton<DatabaseSessionCoordinatorContract>(
    () => DatabaseSessionCoordinator(
      saveSelectedDatabasePathUseCase: sl(),
      getActiveDatabaseUseCase: sl(),
      saveSelectedKeyFilePathUseCase: sl(),
      getSelectedKeyFilePathUseCase: sl(),
      secureDataSource: sl(),
      databaseImportService: sl(),
      resolveDatabaseDuplicateUseCase: sl(),
      upsertDatabaseRecordUseCase: sl(),
      removeDatabaseRecordUseCase: sl(),
      setActiveDatabaseUseCase: sl(),
      getRegisteredDatabasesUseCase: sl(),
      linkDatabaseToDriveUseCase: sl(),
      databaseSyncRepository: sl(),
      getDatabaseSecurityProfileUseCase: sl(),
      saveDatabaseSecurityProfileUseCase: sl(),
      unlockDatabaseUseCase: sl(),
      iosAutofillSnapshotCoordinator: sl<IosAutofillSnapshotCoordinator>(),
    ),
  );

  sl.registerLazySingleton<VaultSessionCoordinator>(
    () => VaultSessionCoordinator(
      saveSelectedDatabasePathUseCase: sl(),
      saveSelectedKeyFilePathUseCase: sl(),
      setActiveDatabaseUseCase: sl(),
      secureDataSource: sl(),
      getRegisteredDatabasesUseCase: sl(),
      upsertDatabaseRecordUseCase: sl(),
      databaseSyncRepository: sl(),
      getDatabaseSecurityProfileUseCase: sl(),
      saveDatabaseSecurityProfileUseCase: sl(),
      vaultKdbxService: sl(),
    ),
  );

  sl.registerFactory(
    () => DatabaseSelectionBloc(databaseSessionCoordinator: sl()),
  );

  sl.registerFactoryParam<DatabaseUnlockBloc, String, void>(
    (databasePath, _) => DatabaseUnlockBloc(
      databasePath: databasePath,
      biometricDataSource: sl(),
      databaseSessionCoordinator: sl(),
    ),
  );

  sl.registerFactoryParam<VaultBloc, String, void>(
    (databasePath, _) => VaultBloc(
      databasePath: databasePath,
      secureDataSource: sl(),
      getSelectedKeyFilePathUseCase: sl(),
      vaultKdbxService: sl(),
      vaultCsvImportService: sl(),
      vaultDuplicateService: sl(),
      getDriveConnectionStatusUseCase: sl(),
      connectGoogleAccountUseCase: sl(),
      disconnectGoogleAccountUseCase: sl(),
      linkDatabaseToDriveUseCase: sl(),
      listDriveRemoteFilesUseCase: sl(),
      syncDatabaseNowUseCase: sl(),
      setDatabaseAutoSyncUseCase: sl(),
      databaseSyncRepository: sl(),
      androidAutofillCoordinator: sl<AndroidAutofillCoordinator>(),
    ),
  );
}
