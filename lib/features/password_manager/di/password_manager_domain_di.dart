import 'package:get_it/get_it.dart';

import '../domain/services/password_generator_service.dart';
import '../domain/usecases/get_active_database_usecase.dart';
import '../domain/usecases/resolve_database_duplicate_usecase.dart';
import '../domain/usecases/unlock_database_usecase.dart';
import '../domain/usecases/validate_database_usecase.dart';

void registerPasswordManagerDomainDependencies(GetIt sl) {
  sl.registerLazySingleton(() => PasswordGeneratorService());
  sl.registerLazySingleton(() => GetActiveDatabaseUseCase(sl()));
  sl.registerLazySingleton(() => ResolveDatabaseDuplicateUseCase(sl()));
  sl.registerLazySingleton(() => UnlockDatabaseUseCase());
  sl.registerLazySingleton(() => ValidateDatabaseUseCase());
}
