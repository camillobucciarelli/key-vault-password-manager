import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/local_data_source.dart';
import 'package:password_manager/features/password_manager/data/datasources/sync_metadata_data_source.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_mapping.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory containerRoot;
  late Directory oldDocs;
  late Directory newDocs;
  late _MutablePathProvider pathProvider;

  setUp(() async {
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
      await SyncMetadataDataSourceImpl().upsertMapping(
        DatabaseSyncMapping(
          databasePath: path,
          driveFileId: 'id',
          driveFileName: 'v.kdbx',
        ),
      );
      final raw = await File(
        p.join(oldDocs.path, 'metadata', 'sync_mappings.json'),
      ).readAsString();
      final decoded = (jsonDecode(raw) as List).single as Map;
      expect(decoded['databasePath'], 'appdocs:databases/v.kdbx');
    });

    test('removeMapping works after a container relocation', () async {
      final oldPath = p.join(oldDocs.path, 'databases', 'v.kdbx');
      await SyncMetadataDataSourceImpl().upsertMapping(
        DatabaseSyncMapping(
          databasePath: oldPath,
          driveFileId: 'id',
          driveFileName: 'v.kdbx',
        ),
      );
      await relocate();

      final newPath = p.join(newDocs.path, 'databases', 'v.kdbx');
      await SyncMetadataDataSourceImpl().removeMapping(newPath);
      expect(await SyncMetadataDataSourceImpl().getAllMappings(), isEmpty);
    });

    test('moveMappingPath re-encodes the new key portably', () async {
      final oldPath = p.join(oldDocs.path, 'databases', 'v.kdbx');
      await SyncMetadataDataSourceImpl().upsertMapping(
        DatabaseSyncMapping(
          databasePath: oldPath,
          driveFileId: 'id',
          driveFileName: 'v.kdbx',
        ),
      );
      await relocate();

      final from = p.join(newDocs.path, 'databases', 'v.kdbx');
      final to = p.join(newDocs.path, 'databases', 'renamed.kdbx');
      await SyncMetadataDataSourceImpl().moveMappingPath(
        fromDatabasePath: from,
        toDatabasePath: to,
      );

      final raw = await File(
        p.join(newDocs.path, 'metadata', 'sync_mappings.json'),
      ).readAsString();
      final decoded = (jsonDecode(raw) as List).single as Map;
      expect(decoded['databasePath'], 'appdocs:databases/renamed.kdbx');
      expect(
        (await SyncMetadataDataSourceImpl().getMapping(to))?.driveFileId,
        'id',
      );
    });

    test('external mapping keys stay absolute on disk (desktop)', () async {
      final external = p.join(containerRoot.path, 'ext', 'v.kdbx');
      await SyncMetadataDataSourceImpl().upsertMapping(
        DatabaseSyncMapping(
          databasePath: external,
          driveFileId: 'id',
          driveFileName: 'v.kdbx',
        ),
      );
      final raw = await File(
        p.join(oldDocs.path, 'metadata', 'sync_mappings.json'),
      ).readAsString();
      expect(
        ((jsonDecode(raw) as List).single as Map)['databasePath'],
        external,
      );
    });
  });

  test(
    'DEFECT (gap): LocalDataSource.cachedKeyFilePath is not portabilized',
    () async {
      final oldKey = p.join(oldDocs.path, 'keys', 'v.keyx');
      await LocalDataSourceImpl().cacheKeyFilePath(oldKey);

      await relocate();

      expect(
        await LocalDataSourceImpl().getCachedKeyFilePath(),
        p.join(newDocs.path, 'keys', 'v.keyx'),
        reason:
            'metadata/local_state.json still stores an absolute key-file path. '
            'It is the unlock-time fallback when no security profile exists '
            '(vault_session_coordinator.dart:69/75/178, '
            'database_session_coordinator.dart:468), so a key-file unlock can '
            'still break after a container relocation.',
      );
    },
  );
}
