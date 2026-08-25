import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/legacy_database_registry_migration.dart';
import 'package:password_manager/features/password_manager/domain/entities/database_record.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_registry_repository.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late SharedPreferences preferences;
  late _FakeRegistryRepository registry;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('legacy_registry_');
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
    registry = _FakeRegistryRepository();
  });

  tearDown(() => root.delete(recursive: true));

  LegacyDatabaseRegistryMigration buildMigration() =>
      LegacyDatabaseRegistryMigration(
        sharedPreferences: preferences,
        registryRepository: registry,
      );

  test(
    'migrates existing and missing paths and restores active record',
    () async {
      final existing = File(p.join(root.path, 'existing.kdbx'));
      await existing.writeAsBytes([1, 2, 3], flush: true);
      final missing = p.join(root.path, 'missing.kdbx');
      await preferences.setStringList(
        LegacyDatabaseRegistryMigration.recentDatabasePathsKey,
        [missing, existing.path],
      );
      await preferences.setString(
        LegacyDatabaseRegistryMigration.cachedDatabasePathKey,
        existing.path,
      );

      await buildMigration().migrate();

      expect(registry.records, hasLength(2));
      final existingRecord = registry.records.singleWhere(
        (record) => record.displayName == 'existing.kdbx',
      );
      final missingRecord = registry.records.singleWhere(
        (record) => record.displayName == 'missing.kdbx',
      );
      expect(
        existingRecord.fileHash,
        md5.convert(await existing.readAsBytes()).toString(),
      );
      expect(missingRecord.fileHash, isNull);
      expect(registry.activeId, existingRecord.databaseId);
      expect(
        preferences.getBool(
          LegacyDatabaseRegistryMigration.migrationCompletedKey,
        ),
        isTrue,
      );
      expect(
        preferences.containsKey(
          LegacyDatabaseRegistryMigration.recentDatabasePathsKey,
        ),
        isFalse,
      );
      expect(
        preferences.containsKey(
          LegacyDatabaseRegistryMigration.cachedDatabasePathKey,
        ),
        isFalse,
      );
    },
  );

  test('authoritative registry ignores stale legacy paths and preserves '
      'active id', () async {
    final path = File(p.join(root.path, 'vault.kdbx'));
    await path.writeAsBytes([1]);
    final stalePath = p.join(root.path, 'removed.kdbx');
    final now = DateTime.utc(2024);
    registry.records.add(
      DatabaseRecord(
        databaseId: 'existing-id',
        canonicalPath: path.path,
        displayName: 'Preserved',
        sourceType: DatabaseSourceType.drive,
        sourceRef: 'remote-id',
        createdAt: now,
        updatedAt: now,
        isFavorite: true,
      ),
    );
    registry.activeId = 'existing-id';
    await preferences.setStringList(
      LegacyDatabaseRegistryMigration.recentDatabasePathsKey,
      [stalePath],
    );
    await preferences.setString(
      LegacyDatabaseRegistryMigration.cachedDatabasePathKey,
      stalePath,
    );

    await buildMigration().migrate();

    expect(registry.records, hasLength(1));
    expect(registry.records.single.databaseId, 'existing-id');
    expect(registry.records.single.sourceRef, 'remote-id');
    expect(registry.records.single.isFavorite, isTrue);
    expect(registry.activeId, 'existing-id');
    expect(
      preferences.getBool(
        LegacyDatabaseRegistryMigration.migrationCompletedKey,
      ),
      isTrue,
    );
    expect(
      preferences.containsKey(
        LegacyDatabaseRegistryMigration.recentDatabasePathsKey,
      ),
      isFalse,
    );
  });

  test(
    'empty registry with no legacy data marks completed as a no-op',
    () async {
      await buildMigration().migrate();

      expect(registry.records, isEmpty);
      expect(registry.activeId, isNull);
      expect(
        preferences.getBool(
          LegacyDatabaseRegistryMigration.migrationCompletedKey,
        ),
        isTrue,
      );
    },
  );

  test('partial registry failure rolls back inserted records and active id, '
      'and keeps legacy data for retry', () async {
    final firstPath = p.join(root.path, 'first.kdbx');
    final secondPath = p.join(root.path, 'second.kdbx');
    await preferences.setStringList(
      LegacyDatabaseRegistryMigration.recentDatabasePathsKey,
      [firstPath, secondPath],
    );
    await preferences.setString(
      LegacyDatabaseRegistryMigration.cachedDatabasePathKey,
      secondPath,
    );
    registry.activeId = 'previous-id';
    registry.failUpsertOnCall = 2;

    await expectLater(buildMigration().migrate(), throwsException);

    expect(registry.records, isEmpty);
    expect(registry.activeId, 'previous-id');
    expect(
      preferences.getBool(
        LegacyDatabaseRegistryMigration.migrationCompletedKey,
      ),
      isNull,
    );
    expect(
      preferences.containsKey(
        LegacyDatabaseRegistryMigration.recentDatabasePathsKey,
      ),
      isTrue,
    );
    expect(
      preferences.containsKey(
        LegacyDatabaseRegistryMigration.cachedDatabasePathKey,
      ),
      isTrue,
    );

    // Retry: the previously-failing call number no longer fails, so the
    // second attempt succeeds without duplicating the first insert.
    await buildMigration().migrate();
    expect(registry.records, hasLength(2));
    expect(
      preferences.containsKey(
        LegacyDatabaseRegistryMigration.recentDatabasePathsKey,
      ),
      isFalse,
    );
  });

  test('marker failure rolls back successful registry writes', () async {
    final path = p.join(root.path, 'vault.kdbx');
    await preferences.setStringList(
      LegacyDatabaseRegistryMigration.recentDatabasePathsKey,
      [path],
    );
    registry.activeId = 'previous-id';
    final migration = LegacyDatabaseRegistryMigration(
      sharedPreferences: preferences,
      registryRepository: registry,
      setBool: (_, _) async => false,
    );

    await expectLater(migration.migrate(), throwsStateError);

    expect(registry.records, isEmpty);
    expect(registry.activeId, 'previous-id');
    expect(
      preferences.getBool(
        LegacyDatabaseRegistryMigration.migrationCompletedKey,
      ),
      isNull,
    );
    expect(
      preferences.containsKey(
        LegacyDatabaseRegistryMigration.recentDatabasePathsKey,
      ),
      isTrue,
    );
  });

  test(
    'completed marker makes a restart a no-op even after cleanup failure',
    () async {
      final path = p.join(root.path, 'vault.kdbx');
      await preferences.setStringList(
        LegacyDatabaseRegistryMigration.recentDatabasePathsKey,
        [path],
      );
      final migration = LegacyDatabaseRegistryMigration(
        sharedPreferences: preferences,
        registryRepository: registry,
        removePreference: (key) async {
          if (key == LegacyDatabaseRegistryMigration.recentDatabasePathsKey) {
            // Cleanup "fails" (returns false) even though the marker below
            // succeeds — the marker, not cleanup success, must be what
            // stops re-import.
            return false;
          }
          return preferences.remove(key);
        },
      );

      await migration.migrate();
      expect(registry.records, hasLength(1));
      expect(
        preferences.getBool(
          LegacyDatabaseRegistryMigration.migrationCompletedKey,
        ),
        isTrue,
      );
      expect(
        preferences.containsKey(
          LegacyDatabaseRegistryMigration.recentDatabasePathsKey,
        ),
        isTrue,
      );

      registry.records.clear();
      registry.activeId = null;
      await buildMigration().migrate();

      expect(
        registry.records,
        isEmpty,
        reason: 'the durable marker must prevent re-import, not cleanup',
      );
    },
  );

  test(
    'completed marker is a no-op even when legacy data still remains',
    () async {
      final path = p.join(root.path, 'stale.kdbx');
      await preferences.setBool(
        LegacyDatabaseRegistryMigration.migrationCompletedKey,
        true,
      );
      await preferences.setStringList(
        LegacyDatabaseRegistryMigration.recentDatabasePathsKey,
        [path],
      );

      await buildMigration().migrate();

      expect(registry.records, isEmpty);
      expect(registry.activeId, isNull);
      expect(
        preferences.containsKey(
          LegacyDatabaseRegistryMigration.recentDatabasePathsKey,
        ),
        isTrue,
      );
    },
  );
}

class _FakeRegistryRepository implements DatabaseRegistryRepository {
  final List<DatabaseRecord> records = [];
  String? activeId;
  int? failUpsertOnCall;
  int upsertCalls = 0;

  @override
  Future<DatabaseRecord?> findByHash(String fileHash) async => null;

  @override
  Future<DatabaseRecord?> findBySource({
    required DatabaseSourceType sourceType,
    required String sourceRef,
  }) async => null;

  @override
  Future<String?> getActive() async => activeId;

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
  Future<List<DatabaseRecord>> list() async => List.of(records);

  @override
  Future<void> remove(String databaseId) async {
    records.removeWhere((record) => record.databaseId == databaseId);
  }

  @override
  Future<void> setActive(String? databaseId) async {
    activeId = databaseId;
  }

  @override
  Future<void> upsert(DatabaseRecord record) async {
    upsertCalls += 1;
    if (failUpsertOnCall == upsertCalls) {
      throw Exception('write failed');
    }
    records.removeWhere((item) => item.databaseId == record.databaseId);
    records.add(record);
  }
}
