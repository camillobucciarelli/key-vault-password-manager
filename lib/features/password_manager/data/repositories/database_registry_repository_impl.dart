import '../../domain/entities/database_record.dart';
import '../../domain/repositories/database_registry_repository.dart';
import '../datasources/database_registry_local_data_source.dart';
import '../models/database_record_model.dart';

class DatabaseRegistryRepositoryImpl implements DatabaseRegistryRepository {
  DatabaseRegistryRepositoryImpl({required this.localDataSource});

  final DatabaseRegistryLocalDataSource localDataSource;

  @override
  Future<List<DatabaseRecord>> list() async {
    final raw = await localDataSource.getRecords();
    return raw
        .map(DatabaseRecordModel.fromMap)
        .map((model) => model.toEntity())
        .toList(growable: false);
  }

  @override
  Future<DatabaseRecord?> getById(String databaseId) async {
    if (databaseId.trim().isEmpty) {
      return null;
    }

    final entries = await list();
    for (final entry in entries) {
      if (entry.databaseId == databaseId) {
        return entry;
      }
    }
    return null;
  }

  @override
  Future<DatabaseRecord?> findBySource({
    required DatabaseSourceType sourceType,
    required String sourceRef,
  }) async {
    final normalizedSourceRef = sourceRef.trim();
    if (normalizedSourceRef.isEmpty) {
      return null;
    }

    final entries = await list();
    for (final entry in entries) {
      if (entry.sourceType == sourceType &&
          entry.sourceRef == normalizedSourceRef) {
        return entry;
      }
    }
    return null;
  }

  @override
  Future<DatabaseRecord?> findByHash(String fileHash) async {
    final normalizedHash = fileHash.trim();
    if (normalizedHash.isEmpty) {
      return null;
    }

    final entries = await list();
    for (final entry in entries) {
      if (entry.fileHash == normalizedHash) {
        return entry;
      }
    }
    return null;
  }

  @override
  Future<void> upsert(DatabaseRecord record) async {
    final existing = await list();
    final next = <DatabaseRecord>[];
    var updated = false;
    for (final entry in existing) {
      if (entry.databaseId == record.databaseId) {
        next.add(record);
        updated = true;
      } else {
        next.add(entry);
      }
    }
    if (!updated) {
      next.add(record);
    }

    final encoded = next
        .map(DatabaseRecordModel.fromEntity)
        .map((model) => model.toMap())
        .toList(growable: false);
    await localDataSource.saveRecords(encoded);
  }

  @override
  Future<void> remove(String databaseId) async {
    if (databaseId.trim().isEmpty) {
      return;
    }

    final existing = await list();
    final next = existing
        .where((entry) => entry.databaseId != databaseId)
        .map(DatabaseRecordModel.fromEntity)
        .map((model) => model.toMap())
        .toList(growable: false);
    await localDataSource.saveRecords(next);

    final active = await getActive();
    if (active == databaseId) {
      await setActive(null);
    }
  }

  @override
  Future<void> setActive(String? databaseId) {
    return localDataSource.saveActiveDatabaseId(databaseId);
  }

  @override
  Future<String?> getActive() {
    return localDataSource.getActiveDatabaseId();
  }
}
