import '../entities/database_record.dart';

abstract class DatabaseRegistryRepository {
  Future<List<DatabaseRecord>> list();
  Future<DatabaseRecord?> getById(String databaseId);
  Future<DatabaseRecord?> findBySource({
    required DatabaseSourceType sourceType,
    required String sourceRef,
  });
  Future<DatabaseRecord?> findByHash(String fileHash);
  Future<void> upsert(DatabaseRecord record);
  Future<void> remove(String databaseId);
  Future<void> setActive(String? databaseId);
  Future<String?> getActive();
}
