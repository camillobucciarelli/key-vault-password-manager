import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/entities/database_record.dart';
import 'package:password_manager/features/password_manager/domain/models/database_dedup_result.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_registry_repository.dart';
import 'package:password_manager/features/password_manager/domain/usecases/resolve_database_duplicate_usecase.dart';

void main() {
  group('ResolveDatabaseDuplicateUseCase', () {
    late _FakeDatabaseRegistryRepository repository;
    late ResolveDatabaseDuplicateUseCase useCase;

    setUp(() {
      repository = _FakeDatabaseRegistryRepository();
      useCase = ResolveDatabaseDuplicateUseCase(repository);
    });

    test('returns source duplicate when sourceRef matches', () async {
      final existing = DatabaseRecord(
        databaseId: 'db1',
        canonicalPath: '/tmp/a.kdbx',
        displayName: 'a.kdbx',
        sourceType: DatabaseSourceType.drive,
        sourceRef: 'drive-file-1',
        fileHash: 'hash-a',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      repository.records = [existing];

      final result = await useCase(
        sourceType: DatabaseSourceType.drive,
        sourceRef: 'drive-file-1',
        fileHash: 'hash-b',
      );

      expect(result.matchType, DatabaseDuplicateMatchType.source);
      expect(result.resolution, DatabaseDuplicateResolution.useExisting);
      expect(result.existingRecord?.databaseId, 'db1');
    });

    test('returns hash duplicate when hash matches', () async {
      final existing = DatabaseRecord(
        databaseId: 'db2',
        canonicalPath: '/tmp/b.kdbx',
        displayName: 'b.kdbx',
        sourceType: DatabaseSourceType.local,
        fileHash: 'same-hash',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      repository.records = [existing];

      final result = await useCase(
        sourceType: DatabaseSourceType.local,
        fileHash: 'same-hash',
      );

      expect(result.matchType, DatabaseDuplicateMatchType.hash);
      expect(result.existingRecord?.databaseId, 'db2');
    });

    test('returns no duplicate when there is no match', () async {
      repository.records = [];

      final result = await useCase(
        sourceType: DatabaseSourceType.local,
        sourceRef: 'x',
        fileHash: 'y',
      );

      expect(result.matchType, DatabaseDuplicateMatchType.none);
      expect(result.hasDuplicate, isFalse);
      expect(result.existingRecord, isNull);
    });
  });
}

class _FakeDatabaseRegistryRepository implements DatabaseRegistryRepository {
  List<DatabaseRecord> records = [];

  @override
  Future<List<DatabaseRecord>> list() async => records;

  @override
  Future<DatabaseRecord?> getById(String databaseId) async {
    for (final record in records) {
      if (record.databaseId == databaseId) {
        return record;
      }
    }
    return null;
  }

  @override
  Future<DatabaseRecord?> findBySource({
    required DatabaseSourceType sourceType,
    required String sourceRef,
  }) async {
    for (final record in records) {
      if (record.sourceType == sourceType && record.sourceRef == sourceRef) {
        return record;
      }
    }
    return null;
  }

  @override
  Future<DatabaseRecord?> findByHash(String fileHash) async {
    for (final record in records) {
      if (record.fileHash == fileHash) {
        return record;
      }
    }
    return null;
  }

  @override
  Future<void> upsert(DatabaseRecord record) async {
    records = [
      ...records.where((item) => item.databaseId != record.databaseId),
      record,
    ];
  }

  @override
  Future<void> remove(String databaseId) async {
    records = records.where((item) => item.databaseId != databaseId).toList();
  }

  @override
  Future<void> setActive(String? databaseId) async {}

  @override
  Future<String?> getActive() async => null;
}
