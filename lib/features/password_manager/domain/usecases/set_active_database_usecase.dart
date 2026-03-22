import '../repositories/database_registry_repository.dart';

class SetActiveDatabaseUseCase {
  SetActiveDatabaseUseCase(this.repository);

  final DatabaseRegistryRepository repository;

  Future<void> call(String? databaseId) {
    return repository.setActive(databaseId);
  }
}
