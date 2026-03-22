import '../entities/database_record.dart';
import '../repositories/database_registry_repository.dart';

class UpsertDatabaseRecordUseCase {
  UpsertDatabaseRecordUseCase(this.repository);

  final DatabaseRegistryRepository repository;

  Future<void> call(DatabaseRecord record) {
    return repository.upsert(record);
  }
}
