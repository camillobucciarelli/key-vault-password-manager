import '../../../../core/utils/portable_path.dart';
import '../../domain/entities/database_record.dart';
import '../../domain/repositories/database_registry_repository.dart';
import '../datasources/database_registry_local_data_source.dart';

class DatabaseRegistryRepositoryImpl implements DatabaseRegistryRepository {
  DatabaseRegistryRepositoryImpl({required this.localDataSource});

  final DatabaseRegistryLocalDataSource localDataSource;

  @override
  Future<List<DatabaseRecord>> list() async {
    final raw = await localDataSource.getRecords();
    final documentsRoot = await PortablePath.documentsRoot();
    return raw
        .map((map) => _recordFromMap(map, documentsRoot))
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

    // Resolved once, outside the loop: symlink resolution is filesystem I/O.
    final resolvedRoot = PortablePath.resolveForComparison(
      await PortablePath.documentsRoot(),
    );
    await localDataSource.saveRecords(
      next
          .map((entry) => _recordToMap(entry, resolvedRoot))
          .toList(growable: false),
    );
  }

  @override
  Future<void> remove(String databaseId) async {
    if (databaseId.trim().isEmpty) {
      return;
    }

    final existing = await list();
    final resolvedRoot = PortablePath.resolveForComparison(
      await PortablePath.documentsRoot(),
    );
    final next = existing
        .where((entry) => entry.databaseId != databaseId)
        .map((entry) => _recordToMap(entry, resolvedRoot))
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

DatabaseRecord _recordFromMap(Map<String, dynamic> map, String documentsRoot) {
  final sourceType = DatabaseSourceType.values.firstWhere(
    (value) => value.name == map['sourceType'],
    orElse: () => DatabaseSourceType.local,
  );
  return DatabaseRecord(
    databaseId: map['databaseId'] as String,
    canonicalPath: PortablePath.decode(
      map['canonicalPath'] as String,
      documentsRoot,
    ),
    displayName: map['displayName'] as String,
    sourceType: sourceType,
    sourceRef: map['sourceRef'] as String?,
    fileHash: map['fileHash'] as String?,
    createdAt: DateTime.parse(map['createdAt'] as String).toLocal(),
    updatedAt: DateTime.parse(map['updatedAt'] as String).toLocal(),
    lastOpenedAt: map['lastOpenedAt'] == null
        ? null
        : DateTime.parse(map['lastOpenedAt'] as String).toLocal(),
    isFavorite: map['isFavorite'] as bool? ?? false,
  );
}

Map<String, dynamic> _recordToMap(DatabaseRecord record, String resolvedRoot) =>
    {
      'databaseId': record.databaseId,
      'canonicalPath': PortablePath.encodeWithResolvedRoot(
        record.canonicalPath,
        resolvedRoot,
      ),
      'displayName': record.displayName,
      'sourceType': record.sourceType.name,
      'sourceRef': record.sourceRef,
      'fileHash': record.fileHash,
      'createdAt': record.createdAt.toUtc().toIso8601String(),
      'updatedAt': record.updatedAt.toUtc().toIso8601String(),
      'lastOpenedAt': record.lastOpenedAt?.toUtc().toIso8601String(),
      'isFavorite': record.isFavorite,
    };
