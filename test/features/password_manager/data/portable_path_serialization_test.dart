import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/database_registry_local_data_source.dart';
import 'package:password_manager/features/password_manager/data/datasources/database_security_local_data_source.dart';
import 'package:password_manager/features/password_manager/data/datasources/sync_metadata_data_source.dart';
import 'package:password_manager/features/password_manager/data/repositories/database_registry_repository_impl.dart';
import 'package:password_manager/features/password_manager/data/repositories/database_security_repository_impl.dart';
import 'package:password_manager/features/password_manager/domain/entities/database_record.dart';
import 'package:password_manager/features/password_manager/domain/entities/database_security_profile.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_mapping.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mirrors the fake used by `sync_metadata_data_source_test.dart`, but the
/// documents root is mutable so a container relocation (iOS reinstall) can be
/// simulated mid-test.
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
    containerRoot = await Directory.systemTemp.createTemp('portable_path_');
    // Stand-ins for /var/mobile/Containers/Data/Application/<UUID>/Documents.
    oldDocs = await Directory(
      p.join(containerRoot.path, 'UUID-A', 'Documents'),
    ).create(recursive: true);
    newDocs = await Directory(
      p.join(containerRoot.path, 'UUID-B', 'Documents'),
    ).create(recursive: true);

    pathProvider = _MutablePathProvider(oldDocs.path);
    PathProviderPlatform.instance = pathProvider;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    await containerRoot.delete(recursive: true);
  });

  /// Copies the persisted metadata written under the old documents root into
  /// the new one, exactly like iOS carrying the container contents across a
  /// reinstall while renaming the parent UUID.
  Future<void> relocateContainer() async {
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

  Future<DatabaseRegistryRepositoryImpl> buildRegistry() async {
    return DatabaseRegistryRepositoryImpl(
      localDataSource: DatabaseRegistryLocalDataSourceImpl(
        sharedPreferences: await SharedPreferences.getInstance(),
      ),
    );
  }

  DatabaseRecord buildRecord(String canonicalPath) {
    final now = DateTime.utc(2024, 1, 1);
    return DatabaseRecord(
      databaseId: 'db-1',
      canonicalPath: canonicalPath,
      displayName: 'Vault',
      sourceType: DatabaseSourceType.local,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('DatabaseRegistryRepositoryImpl path portability', () {
    test(
      'record inside app documents resolves against the new documents root',
      () async {
        final oldPath = p.join(oldDocs.path, 'databases', 'vault.kdbx');
        await (await buildRegistry()).upsert(buildRecord(oldPath));

        await relocateContainer();

        final records = await (await buildRegistry()).list();
        expect(records, hasLength(1));
        expect(
          records.single.canonicalPath,
          p.join(newDocs.path, 'databases', 'vault.kdbx'),
        );
        expect(records.single.canonicalPath, isNot(oldPath));
      },
    );

    test('the sentinel really reaches disk', () async {
      await (await buildRegistry()).upsert(
        buildRecord(p.join(oldDocs.path, 'databases', 'vault.kdbx')),
      );

      final raw = await File(
        p.join(oldDocs.path, 'metadata', 'database_registry_records.json'),
      ).readAsString();
      final decoded = (jsonDecode(raw) as List).single as Map;
      expect(decoded['canonicalPath'], 'appdocs:databases/vault.kdbx');
    });

    test('external path stays absolute on disk', () async {
      final externalPath = p.join(containerRoot.path, 'external', 'vault.kdbx');
      await (await buildRegistry()).upsert(buildRecord(externalPath));

      final raw = await File(
        p.join(oldDocs.path, 'metadata', 'database_registry_records.json'),
      ).readAsString();
      final decoded = (jsonDecode(raw) as List).single as Map;
      expect(decoded['canonicalPath'], externalPath);
    });

    test('path outside app documents round-trips unchanged', () async {
      final externalPath = p.join(containerRoot.path, 'external', 'vault.kdbx');
      await (await buildRegistry()).upsert(buildRecord(externalPath));

      await relocateContainer();

      final records = await (await buildRegistry()).list();
      expect(records.single.canonicalPath, externalPath);
    });

    test('legacy absolute record loads unchanged, without migration', () async {
      // Written the way the pre-fix build persisted it: a frozen absolute path
      // under the *old* container UUID.
      final legacyPath = p.join(oldDocs.path, 'databases', 'legacy.kdbx');
      final metadata = await Directory(
        p.join(oldDocs.path, 'metadata'),
      ).create(recursive: true);
      // Built with `jsonEncode` rather than as a hand-written literal. The
      // literal interpolated the path straight into JSON source, which is only
      // valid while the path contains no backslash: on Windows `legacyPath` is
      // `C:\Users\...`, and `\U` is not a legal JSON string escape, so the
      // fixture failed to parse before the code under test was ever reached.
      // Production writes this file with `jsonEncode` too, so this is also the
      // more faithful reproduction of a pre-fix record.
      await File(
        p.join(metadata.path, 'database_registry_records.json'),
      ).writeAsString(
        jsonEncode([
          {
            'databaseId': 'legacy',
            'canonicalPath': legacyPath,
            'displayName': 'Legacy',
            'sourceType': 'local',
            'sourceRef': null,
            'fileHash': null,
            'createdAt': '2024-01-01T00:00:00.000Z',
            'updatedAt': '2024-01-01T00:00:00.000Z',
            'lastOpenedAt': null,
            'isFavorite': false,
          },
        ]),
      );

      await relocateContainer();

      final records = await (await buildRegistry()).list();
      expect(records.single.canonicalPath, legacyPath);
    });
  });

  group('DatabaseSecurityRepositoryImpl keyFilePath portability', () {
    Future<DatabaseSecurityRepositoryImpl> buildSecurity() async =>
        DatabaseSecurityRepositoryImpl(
          localDataSource: DatabaseSecurityLocalDataSourceImpl(),
        );

    test('key file inside app documents follows the new root', () async {
      final oldKeyPath = p.join(oldDocs.path, 'keys', 'vault.keyx');
      await (await buildSecurity()).saveProfile(
        DatabaseSecurityProfile(databaseId: 'db-1', keyFilePath: oldKeyPath),
      );

      await relocateContainer();

      final profile = await (await buildSecurity()).getProfile('db-1');
      expect(profile!.keyFilePath, p.join(newDocs.path, 'keys', 'vault.keyx'));
    });

    test('the sentinel really reaches disk', () async {
      await (await buildSecurity()).saveProfile(
        DatabaseSecurityProfile(
          databaseId: 'db-1',
          keyFilePath: p.join(oldDocs.path, 'keys', 'vault.keyx'),
        ),
      );

      final raw = await File(
        p.join(oldDocs.path, 'metadata', 'database_security_profiles.json'),
      ).readAsString();
      final decoded = (jsonDecode(raw) as Map)['db-1'] as Map;
      expect(decoded['keyFilePath'], 'appdocs:keys/vault.keyx');
    });

    test('external key file stays absolute on disk', () async {
      final externalKey = p.join(containerRoot.path, 'usb', 'vault.keyx');
      await (await buildSecurity()).saveProfile(
        DatabaseSecurityProfile(databaseId: 'db-1', keyFilePath: externalKey),
      );

      final raw = await File(
        p.join(oldDocs.path, 'metadata', 'database_security_profiles.json'),
      ).readAsString();
      final decoded = (jsonDecode(raw) as Map)['db-1'] as Map;
      expect(decoded['keyFilePath'], externalKey);
    });

    test('external key file and null key file are preserved', () async {
      final externalKey = p.join(containerRoot.path, 'usb', 'vault.keyx');
      final security = await buildSecurity();
      await security.saveProfile(
        DatabaseSecurityProfile(databaseId: 'db-1', keyFilePath: externalKey),
      );
      await security.saveProfile(
        const DatabaseSecurityProfile(databaseId: 'db-2'),
      );

      await relocateContainer();

      final relocated = await buildSecurity();
      expect((await relocated.getProfile('db-1'))!.keyFilePath, externalKey);
      expect((await relocated.getProfile('db-2'))!.keyFilePath, isNull);
    });
  });

  group('SyncMetadataDataSource databasePath portability', () {
    test('mapping key follows the new documents root', () async {
      final oldPath = p.join(oldDocs.path, 'databases', 'vault.kdbx');
      await SyncMetadataDataSourceImpl().upsertMapping(
        DatabaseSyncMapping(
          databasePath: oldPath,
          driveFileId: 'drive-id',
          driveFileName: 'vault.kdbx',
        ),
      );

      await relocateContainer();

      final newPath = p.join(newDocs.path, 'databases', 'vault.kdbx');
      final mapping = await SyncMetadataDataSourceImpl().getMapping(newPath);
      expect(mapping, isNotNull);
      expect(mapping!.driveFileId, 'drive-id');
      expect(mapping.databasePath, newPath);
    });

    test('external mapping key round-trips unchanged', () async {
      final externalPath = p.join(containerRoot.path, 'external', 'vault.kdbx');
      await SyncMetadataDataSourceImpl().upsertMapping(
        DatabaseSyncMapping(
          databasePath: externalPath,
          driveFileId: 'drive-id',
          driveFileName: 'vault.kdbx',
        ),
      );

      await relocateContainer();

      final mapping = await SyncMetadataDataSourceImpl().getMapping(
        externalPath,
      );
      expect(mapping, isNotNull);
      expect(mapping!.databasePath, externalPath);
    });
  });
}
