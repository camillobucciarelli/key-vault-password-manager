import '../repositories/database_registry_repository.dart';

class RemoveDatabaseRecordUseCase {
  RemoveDatabaseRecordUseCase(this.repository);

  final DatabaseRegistryRepository repository;

  Future<void> call(String databaseId) {
    return repository.remove(databaseId);
  }
}
