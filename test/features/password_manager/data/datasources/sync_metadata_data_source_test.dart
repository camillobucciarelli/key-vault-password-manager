import 'dart:convert';
import 'dart:io';
import 'in_memory_secure_data_source.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/core/utils/managed_storage_root.dart';
import 'package:password_manager/features/password_manager/data/datasources/metadata_cipher.dart';
import 'package:password_manager/features/password_manager/data/datasources/sync_metadata_data_source.dart';
import 'package:path/path.dart' as p;
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
          providerId: 'google_drive',
          remoteFileId: 'drive-id',
          remoteFileName: 'vault.kdbx',
        ),
      );

      await dataSource.moveMappingPath(
        fromDatabasePath: oldPath,
        toDatabasePath: newPath,
      );

      final mapping = await dataSource.getMapping('db-1');
      expect(mapping, isNotNull);
      expect(mapping!.databasePath, newPath);
      expect(mapping.remoteFileId, 'drive-id');
    });
  });

  group('spec 010 mapping migration (T103/T104)', () {
    late InMemorySecureDataSource secure;
    late EncryptedMetadataStore store;
    late File mappingsFile;

    setUp(() async {
      secure = InMemorySecureDataSource();
      store = EncryptedMetadataStore(secureDataSource: secure);
      final root = await ManagedStorageRoot.resolveDirectory();
      final dir = Directory(p.join(root.path, 'metadata'));
      await dir.create(recursive: true);
      mappingsFile = File(p.join(dir.path, 'sync_mappings.json'));
    });

    const v1 = <String, dynamic>{
      'databaseId': 'db-1',
      'databasePath': '/tmp/legacy.kdbx',
      'driveFileId': 'legacy-remote-id',
      'driveFileName': 'legacy.kdbx',
      'lastSyncedLocalChecksum': 'local-sum',
      'lastSyncedRemoteChecksum': 'remote-sum',
      'lastSyncedRemoteModifiedTime': '2026-01-02T03:04:05.000Z',
      'lastSyncAt': '2026-01-03T00:00:00.000Z',
      'autoSyncEnabled': false,
      'lastError': 'old error',
    };

    test(
      'a v1 file decodes as google_drive and reading rewrites nothing',
      () async {
        await store.writeString(mappingsFile, jsonEncode([v1]));
        final rawBefore = await store.readString(mappingsFile);
        final dataSource = SyncMetadataDataSourceImpl(secureDataSource: secure);

        final mapping = (await dataSource.getMapping('db-1'))!;
        await dataSource.getAllMappings();

        expect(mapping.providerId, 'google_drive');
        expect(mapping.remoteFileId, 'legacy-remote-id');
        expect(mapping.remoteFileName, 'legacy.kdbx');
        expect(mapping.lastSyncedLocalChecksum, 'local-sum');
        expect(mapping.lastSyncedRemoteChecksum, 'remote-sum');
        expect(mapping.autoSyncEnabled, isFalse);
        expect(mapping.lastError, 'old error');
        expect(
          await store.readString(mappingsFile),
          rawBefore,
          reason: 'reads are side-effect free',
        );
      },
    );

    test(
      'the next successful save writes every mapping forward as v2',
      () async {
        await store.writeString(mappingsFile, jsonEncode([v1]));
        final dataSource = SyncMetadataDataSourceImpl(secureDataSource: secure);
        final mapping = (await dataSource.getMapping('db-1'))!;

        await dataSource.upsertMapping(
          'db-1',
          mapping.copyWith(autoSyncEnabled: true),
        );

        final raw = jsonDecode((await store.readString(mappingsFile))!) as List;
        final entry = raw.single as Map<String, dynamic>;
        expect(entry['schemaVersion'], 2);
        expect(entry['providerId'], 'google_drive');
        expect(entry['remoteFileId'], 'legacy-remote-id');
        expect(entry['remoteFileName'], 'legacy.kdbx');
        expect(entry.containsKey('driveFileId'), isFalse);
        expect(entry.containsKey('driveFileName'), isFalse);
        expect(entry['lastSyncedLocalChecksum'], 'local-sum');
        expect(entry['lastSyncedRemoteChecksum'], 'remote-sum');
        expect(
          entry['lastSyncedRemoteModifiedTime'],
          '2026-01-02T03:04:05.000Z',
        );
        expect(entry['lastSyncAt'], '2026-01-03T00:00:00.000Z');
        expect(entry['autoSyncEnabled'], isTrue);
        expect(entry['lastError'], 'old error');

        final again = (await dataSource.getMapping('db-1'))!;
        expect(again.remoteFileId, 'legacy-remote-id');
        expect(again.autoSyncEnabled, isTrue);
      },
    );

    test(
      'a malformed mapping fails closed: nothing dropped, nothing rewritten',
      () async {
        final malformed = {...v1}..remove('driveFileId');
        await store.writeString(mappingsFile, jsonEncode([v1, malformed]));
        final rawBefore = await store.readString(mappingsFile);
        final dataSource = SyncMetadataDataSourceImpl(secureDataSource: secure);

        await expectLater(
          dataSource.getAllMappings(),
          throwsA(isA<SyncMappingDecodeException>()),
        );
        await expectLater(
          dataSource.upsertMapping(
            'db-2',
            const DatabaseSyncMapping(
              databasePath: '/tmp/new.kdbx',
              providerId: 'google_drive',
              remoteFileId: 'x',
              remoteFileName: 'x.kdbx',
            ),
          ),
          throwsA(isA<SyncMappingDecodeException>()),
        );
        expect(await store.readString(mappingsFile), rawBefore);
      },
    );
  });
}
