import 'package:get_it/get_it.dart';

import '../presentation/bloc/database_selection/database_selection_bloc.dart';
import '../presentation/bloc/database_unlock/database_unlock_bloc.dart';
import '../presentation/bloc/vault/vault_bloc.dart';

void registerPasswordManagerPresentationDependencies(GetIt sl) {
  sl.registerFactory(
    () => DatabaseSelectionBloc(
      getSelectedDatabasePathUseCase: sl(),
      saveSelectedDatabasePathUseCase: sl(),
      saveSelectedKeyFilePathUseCase: sl(),
      setBiometricProtectionEnabledUseCase: sl(),
      secureDataSource: sl(),
      validateDatabaseUseCase: sl(),
      linkDatabaseToDriveUseCase: sl(),
    ),
  );

  sl.registerFactoryParam<DatabaseUnlockBloc, String, void>(
    (databasePath, _) => DatabaseUnlockBloc(
      databasePath: databasePath,
      getSelectedKeyFilePathUseCase: sl(),
      saveSelectedKeyFilePathUseCase: sl(),
      getBiometricProtectionEnabledUseCase: sl(),
      biometricDataSource: sl(),
      secureDataSource: sl(),
      unlockDatabaseUseCase: sl(),
    ),
  );

  sl.registerFactoryParam<VaultBloc, String, void>(
    (databasePath, _) => VaultBloc(
      databasePath: databasePath,
      secureDataSource: sl(),
      getSelectedKeyFilePathUseCase: sl(),
      vaultKdbxService: sl(),
      vaultCsvImportService: sl(),
      getDriveConnectionStatusUseCase: sl(),
      connectGoogleAccountUseCase: sl(),
      disconnectGoogleAccountUseCase: sl(),
      linkDatabaseToDriveUseCase: sl(),
      listDriveRemoteFilesUseCase: sl(),
      syncDatabaseNowUseCase: sl(),
      setDatabaseAutoSyncUseCase: sl(),
      databaseSyncRepository: sl(),
    ),
  );
}
