import 'dart:io';
import 'in_memory_secure_data_source.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/sync_metadata_data_source.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_mapping.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String basePath;
  _FakePathProvider(this.basePath);

  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;

  @override
  Future<String?> getApplicationSupportPath() async => basePath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_metadata_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('SyncMetadataDataSource', () {
    test('moveMappingPath updates the path payload; the id key is stable '
        '(spec 014 FR-6)', () async {
      final dataSource = SyncMetadataDataSourceImpl(
        secureDataSource: InMemorySecureDataSource(),
      );

      const oldPath = '/tmp/old.kdbx';
      const newPath = '/tmp/new.kdbx';
      await dataSource.upsertMapping(
        'db-1',
        const DatabaseSyncMapping(
          databasePath: oldPath,
          driveFileId: 'drive-id',
          driveFileName: 'vault.kdbx',
        ),
      );

      await dataSource.moveMappingPath(
        fromDatabasePath: oldPath,
        toDatabasePath: newPath,
      );

      final mapping = await dataSource.getMapping('db-1');
      expect(mapping, isNotNull);
      expect(mapping!.databasePath, newPath);
      expect(mapping.driveFileId, 'drive-id');
    });
  });
}
