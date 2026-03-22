import '../entities/database_record.dart';
import '../repositories/database_registry_repository.dart';

class GetActiveDatabaseUseCase {
  GetActiveDatabaseUseCase(this.repository);

  final DatabaseRegistryRepository repository;

  Future<DatabaseRecord?> call() async {
    final activeId = await repository.getActive();
    if (activeId == null || activeId.trim().isEmpty) {
      return null;
    }
    return repository.getById(activeId);
  }
}
