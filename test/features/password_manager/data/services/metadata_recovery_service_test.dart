import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/database_registry_local_data_source.dart';
import 'package:password_manager/features/password_manager/data/services/metadata_recovery_service.dart';
import 'package:password_manager/features/password_manager/domain/errors/database_access_failure.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../datasources/in_memory_secure_data_source.dart';

/// spec 014 FR-5: the user-initiated recovery from a lost metadata key.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late InMemorySecureDataSource secure;
  late MetadataRecoveryService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('metadata_recovery_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    SharedPreferences.setMockInitialValues(const {});
    secure = InMemorySecureDataSource();
    service = MetadataRecoveryService(secureDataSource: secure);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<DatabaseRegistryLocalDataSourceImpl> registry() async =>
      DatabaseRegistryLocalDataSourceImpl(
        sharedPreferences: await SharedPreferences.getInstance(),
        secureDataSource: secure,
      );

  List<File> metadataFiles() =>
      Directory(p.join(tempDir.path, 'metadata')).listSync().whereType<File>()
          .toList();

  test('nothing to recover when there is no metadata at all', () async {
    expect(await service.hasUnreadableMetadata(), isFalse);
    expect(await service.discardUnreadableMetadata(), 0);
  });

  test('readable metadata is never reported or discarded', () async {
    await (await registry()).saveRecords([
      {'databaseId': 'db_1', 'displayName': 'Mine.kdbx'},
    ]);

    expect(await service.hasUnreadableMetadata(), isFalse);
    expect(await service.discardUnreadableMetadata(), 0);
    expect(
      (await (await registry()).getRecords()).single['displayName'],
      'Mine.kdbx',
    );
  });

  test('an unreachable store is not "unreadable metadata": its data is '
      'intact and must not be discarded', () async {
    await (await registry()).saveRecords([
      {'databaseId': 'db_1', 'displayName': 'Mine.kdbx'},
    ]);

    secure.unavailable = true;

    expect(await service.hasUnreadableMetadata(), isFalse);
    expect(await service.discardUnreadableMetadata(), 0);
  });

  test('a lost key blocks writes until the user discards the metadata, '
      'which is moved aside rather than deleted', () async {
    await (await registry()).saveRecords([
      {'databaseId': 'db_1', 'displayName': 'Mine.kdbx'},
    ]);
    final originalBytes = metadataFiles().single.readAsBytesSync();

    secure.entries.remove('METADATA_ENCRYPTION_KEY');
    expect(await service.hasUnreadableMetadata(), isTrue);
    await expectLater(
      (await registry()).saveRecords([
        {'databaseId': 'db_2', 'displayName': 'Other.kdbx'},
      ]),
      throwsA(isA<MetadataStorageUnreadableFailure>()),
    );

    expect(await service.discardUnreadableMetadata(), 1);
    expect(await service.hasUnreadableMetadata(), isFalse);

    final orphaned = metadataFiles().single;
    expect(
      p.basename(orphaned.path),
      startsWith('database_registry_records.json.orphaned-'),
    );
    expect(
      orphaned.readAsBytesSync(),
      originalBytes,
      reason: 'the unreadable bytes survive, they are not destroyed',
    );

    // The write that was refused now succeeds under a freshly minted key.
    await (await registry()).saveRecords([
      {'databaseId': 'db_2', 'displayName': 'Other.kdbx'},
    ]);
    expect(
      (await (await registry()).getRecords()).single['displayName'],
      'Other.kdbx',
    );
  });
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.basePath);

  final String basePath;

  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;

  @override
  Future<String?> getApplicationSupportPath() async => basePath;
}
