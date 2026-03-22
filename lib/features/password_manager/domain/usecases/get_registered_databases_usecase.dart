import '../entities/database_record.dart';
import '../repositories/database_registry_repository.dart';

class GetRegisteredDatabasesUseCase {
  GetRegisteredDatabasesUseCase(this.repository);

  final DatabaseRegistryRepository repository;

  Future<List<DatabaseRecord>> call() {
    return repository.list();
  }
}
