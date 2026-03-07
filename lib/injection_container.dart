import 'package:flutter_autofill_service/flutter_autofill_service.dart';
import 'package:get_it/get_it.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/password_manager/data/datasources/biometric_data_source.dart';
import 'features/password_manager/data/datasources/ios_autofill_data_source.dart';
import 'features/password_manager/data/datasources/local_data_source.dart';
import 'features/password_manager/data/datasources/secure_data_source.dart';
import 'features/password_manager/data/services/android_autofill_coordinator.dart';
import 'features/password_manager/data/services/desktop_autofill_bridge_service.dart';
import 'features/password_manager/data/services/ios_autofill_snapshot_coordinator.dart';
import 'features/password_manager/data/repositories/database_repository_impl.dart';
import 'features/password_manager/data/services/vault_kdbx_service.dart';
import 'features/password_manager/domain/repositories/database_repository.dart';
import 'features/password_manager/domain/services/vault_autofill_matcher.dart';
import 'features/password_manager/domain/usecases/get_biometric_protection_enabled_usecase.dart';
import 'features/password_manager/domain/usecases/get_selected_database_path_usecase.dart';
import 'features/password_manager/domain/usecases/get_selected_key_file_path_usecase.dart';
import 'features/password_manager/domain/usecases/save_selected_database_path_usecase.dart';
import 'features/password_manager/domain/usecases/save_selected_key_file_path_usecase.dart';
import 'features/password_manager/domain/usecases/set_biometric_protection_enabled_usecase.dart';
import 'features/password_manager/domain/usecases/unlock_database_usecase.dart';
import 'features/password_manager/domain/usecases/validate_database_usecase.dart';
import 'features/password_manager/presentation/bloc/database_unlock/database_unlock_bloc.dart';
import 'features/password_manager/presentation/bloc/database_selection/database_selection_bloc.dart';
import 'features/password_manager/presentation/bloc/vault/vault_bloc.dart';

final sl = GetIt.instance;

Future<void> init() async {
  // Features - Password Manager
  // Bloc
  sl.registerFactory(
    () => DatabaseSelectionBloc(
      getSelectedDatabasePathUseCase: sl(),
      saveSelectedDatabasePathUseCase: sl(),
      saveSelectedKeyFilePathUseCase: sl(),
      setBiometricProtectionEnabledUseCase: sl(),
      secureDataSource: sl(),
      validateDatabaseUseCase: sl(),
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
    ),
  );

  // Use cases
  sl.registerLazySingleton(() => GetSelectedDatabasePathUseCase(sl()));
  sl.registerLazySingleton(() => SaveSelectedDatabasePathUseCase(sl()));
  sl.registerLazySingleton(() => GetSelectedKeyFilePathUseCase(sl()));
  sl.registerLazySingleton(() => SaveSelectedKeyFilePathUseCase(sl()));
  sl.registerLazySingleton(() => GetBiometricProtectionEnabledUseCase(sl()));
  sl.registerLazySingleton(() => SetBiometricProtectionEnabledUseCase(sl()));
  sl.registerLazySingleton(() => UnlockDatabaseUseCase());
  sl.registerLazySingleton(() => ValidateDatabaseUseCase());

  // Repository
  sl.registerLazySingleton<DatabaseRepository>(
    () => DatabaseRepositoryImpl(localDataSource: sl()),
  );

  // Data sources
  sl.registerLazySingleton<LocalDataSource>(
    () => LocalDataSourceImpl(sharedPreferences: sl()),
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
  sl.registerLazySingleton(() => VaultAutofillMatcher());
  sl.registerLazySingleton(() => VaultKdbxService());
  sl.registerLazySingleton(
    () => AndroidAutofillCoordinator(
      autofillService: sl(),
      getSelectedDatabasePathUseCase: sl(),
      getSelectedKeyFilePathUseCase: sl(),
      secureDataSource: sl(),
      vaultKdbxService: sl(),
      matcher: sl(),
    ),
  );
  sl.registerLazySingleton(
    () => IosAutofillSnapshotCoordinator(
      getSelectedDatabasePathUseCase: sl(),
      getSelectedKeyFilePathUseCase: sl(),
      secureDataSource: sl(),
      vaultKdbxService: sl(),
      iosAutofillDataSource: sl(),
    ),
  );
  sl.registerLazySingleton(
    () => DesktopAutofillBridgeService(
      getSelectedDatabasePathUseCase: sl(),
      getSelectedKeyFilePathUseCase: sl(),
      secureDataSource: sl(),
      vaultKdbxService: sl(),
      matcher: sl(),
    ),
  );

  // External
  final sharedPreferences = await SharedPreferences.getInstance();
  sl.registerLazySingleton(() => sharedPreferences);
  sl.registerLazySingleton(() => AutofillService());
  sl.registerLazySingleton(() => const FlutterSecureStorage());
  sl.registerLazySingleton(() => LocalAuthentication());
}
