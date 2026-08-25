import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/secure_data_source.dart';
import 'package:password_manager/features/password_manager/data/services/legacy_database_registry_migration.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_registry_repository.dart';
import 'package:password_manager/injection_container.dart' as di;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// spec-011 FR-6 wiring test: the startup migration must run from `di.init()`
/// itself, before any widget exists. Removing the call in `init()` makes this
/// test fail — it kills the "delete the migration call" mutation that the
/// data-source unit tests cannot see.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  final deletedKeys = <String>[];
  late Directory documentsDirectory;

  setUp(() async {
    documentsDirectory = await Directory.systemTemp.createTemp(
      'injection_container_test_',
    );
    PathProviderPlatform.instance = _FakePathProvider(documentsDirectory.path);
    deletedKeys.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          if (call.method == 'delete') {
            final arguments = call.arguments as Map<Object?, Object?>;
            deletedKeys.add(arguments['key']! as String);
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    await di.sl.reset();
    await documentsDirectory.delete(recursive: true);
  });

  test('di.init() deletes the legacy global master password entry', () async {
    await di.init();

    expect(deletedKeys, contains(SecureDataSourceImpl.legacyMasterPasswordKey));
  });

  test('di.init() migrates legacy database paths before UI startup', () async {
    final missingPath = '${documentsDirectory.path}/missing.kdbx';
    SharedPreferences.setMockInitialValues({
      LegacyDatabaseRegistryMigration.recentDatabasePathsKey: [missingPath],
      LegacyDatabaseRegistryMigration.cachedDatabasePathKey: missingPath,
    });

    await di.init();

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.containsKey(
        LegacyDatabaseRegistryMigration.recentDatabasePathsKey,
      ),
      isFalse,
    );
    final records = await di.sl<DatabaseRegistryRepository>().list();
    expect(records, hasLength(1));
    expect(records.single.canonicalPath, missingPath);
    expect(await di.sl<DatabaseRegistryRepository>().getActive(), isNotNull);
  });

  test(
    'di.init() reconciles a missing registry hash before UI startup',
    () async {
      final database = File('${documentsDirectory.path}/vault.kdbx');
      await database.writeAsBytes([1, 2, 3], flush: true);
      final metadataDirectory = Directory(
        '${documentsDirectory.path}/metadata',
      );
      await metadataDirectory.create();
      final now = DateTime.utc(2026).toIso8601String();
      await File(
        '${metadataDirectory.path}/database_registry_records.json',
      ).writeAsString(
        jsonEncode([
          {
            'databaseId': 'db-1',
            'canonicalPath': database.path,
            'displayName': 'vault.kdbx',
            'sourceType': 'local',
            'sourceRef': null,
            'fileHash': null,
            'createdAt': now,
            'updatedAt': now,
            'lastOpenedAt': null,
            'isFavorite': false,
          },
        ]),
        flush: true,
      );

      await di.init();

      final records = await di.sl<DatabaseRegistryRepository>().list();
      expect(records.single.fileHash, md5.convert([1, 2, 3]).toString());
    },
  );
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.documentsPath);

  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}
