import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/metadata_cipher.dart';
import 'package:password_manager/features/password_manager/data/datasources/sync_metadata_data_source.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_mapping.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'datasources/in_memory_secure_data_source.dart';

/// Regression probes for `fix/ios-portable-database-paths`: the sentinel that
/// actually reaches disk, the sync-mapping mutators operating over portable
/// keys, and the `local_state.json` key-file cache surviving a container
/// relocation.
class _MutablePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _MutablePathProvider(this.basePath);

  String basePath;

  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;

  @override
  Future<String?> getApplicationSupportPath() async => basePath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory containerRoot;
  late Directory oldDocs;
  late Directory newDocs;
  late _MutablePathProvider pathProvider;
  // One secure store across relocations: the metadata key lives in the
  // platform keystore, which survives a container-UUID rotation.
  late InMemorySecureDataSource secure;

  setUp(() async {
    secure = InMemorySecureDataSource();
    containerRoot = await Directory.systemTemp.createTemp('portable_regr_');
    oldDocs = await Directory(
      p.join(containerRoot.path, 'UUID-A', 'Documents'),
    ).create(recursive: true);
    newDocs = await Directory(
      p.join(containerRoot.path, 'UUID-B', 'Documents'),
    ).create(recursive: true);
    pathProvider = _MutablePathProvider(oldDocs.path);
    PathProviderPlatform.instance = pathProvider;
  });

  tearDown(() async {
    await containerRoot.delete(recursive: true);
  });

  Future<String> readSealed(String path) async {
    final key = base64Decode(secure.entries['METADATA_ENCRYPTION_KEY']!);
    return utf8.decode(
      MetadataCipher.open(key, await File(path).readAsBytes()),
    );
  }

  Future<void> relocate() async {
    final source = Directory(p.join(oldDocs.path, 'metadata'));
    if (await source.exists()) {
      final target = Directory(p.join(newDocs.path, 'metadata'));
      await target.create(recursive: true);
      await for (final entry in source.list(followLinks: false)) {
        if (entry is File) {
          await entry.copy(p.join(target.path, p.basename(entry.path)));
        }
      }
    }
    pathProvider.basePath = newDocs.path;
  }

  group('sync mapping mutators still work over portable keys', () {
    test('the sentinel really reaches disk', () async {
      final path = p.join(oldDocs.path, 'databases', 'v.kdbx');
      await SyncMetadataDataSourceImpl(secureDataSource: secure).upsertMapping(
        'db-1',
        DatabaseSyncMapping(
          databasePath: path,
          driveFileId: 'id',
          driveFileName: 'v.kdbx',
        ),
      );
      final raw = await readSealed(
        p.join(oldDocs.path, 'metadata', 'sync_mappings.json'),
      );
      final decoded = (jsonDecode(raw) as List).single as Map;
      expect(decoded['databasePath'], 'appdocs:databases/v.kdbx');
    });

    test('removeMapping works after a container relocation', () async {
      final oldPath = p.join(oldDocs.path, 'databases', 'v.kdbx');
      await SyncMetadataDataSourceImpl(secureDataSource: secure).upsertMapping(
        'db-1',
        DatabaseSyncMapping(
          databasePath: oldPath,
          driveFileId: 'id',
          driveFileName: 'v.kdbx',
        ),
      );
      await relocate();

      await SyncMetadataDataSourceImpl(
        secureDataSource: secure,
      ).removeMapping('db-1');
      expect(
        await SyncMetadataDataSourceImpl(
          secureDataSource: secure,
        ).getAllMappings(),
        isEmpty,
      );
    });

    test('moveMappingPath re-encodes the new key portably', () async {
      final oldPath = p.join(oldDocs.path, 'databases', 'v.kdbx');
      await SyncMetadataDataSourceImpl(secureDataSource: secure).upsertMapping(
        'db-1',
        DatabaseSyncMapping(
          databasePath: oldPath,
          driveFileId: 'id',
          driveFileName: 'v.kdbx',
        ),
      );
      await relocate();

      final from = p.join(newDocs.path, 'databases', 'v.kdbx');
      final to = p.join(newDocs.path, 'databases', 'renamed.kdbx');
      await SyncMetadataDataSourceImpl(
        secureDataSource: secure,
      ).moveMappingPath(fromDatabasePath: from, toDatabasePath: to);

      final raw = await readSealed(
        p.join(newDocs.path, 'metadata', 'sync_mappings.json'),
      );
      final decoded = (jsonDecode(raw) as List).single as Map;
      expect(decoded['databasePath'], 'appdocs:databases/renamed.kdbx');
      expect(
        (await SyncMetadataDataSourceImpl(
          secureDataSource: secure,
        ).getMapping('db-1'))?.driveFileId,
        'id',
      );
    });

    test('external mapping keys stay absolute on disk (desktop)', () async {
      final external = p.join(containerRoot.path, 'ext', 'v.kdbx');
      await SyncMetadataDataSourceImpl(secureDataSource: secure).upsertMapping(
        'db-1',
        DatabaseSyncMapping(
          databasePath: external,
          driveFileId: 'id',
          driveFileName: 'v.kdbx',
        ),
      );
      final raw = await readSealed(
        p.join(oldDocs.path, 'metadata', 'sync_mappings.json'),
      );
      expect(
        ((jsonDecode(raw) as List).single as Map)['databasePath'],
        external,
      );
    });
  });
}
