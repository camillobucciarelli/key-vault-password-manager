import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/database_import_service.dart';
import 'package:password_manager/features/password_manager/domain/usecases/validate_database_usecase.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Spec 014 FR-3 / AC-1 (T006) and FR-1 (T006b).
///
/// A managed directory listing must reveal nothing: no human-readable name,
/// no `.kdbx`/`.key` extension, and no value from which the database-to-key
/// association could be rebuilt. Importing keeps the user's original file
/// untouched.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const validKdbxHeader = [0x03, 0xD9, 0xA2, 0x9A, 0x67, 0xFB, 0x4B, 0xB5];
  final opaque = RegExp(r'^[0-9a-f]{32}$');

  late Directory tempDir;
  late DatabaseImportService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('opaque_naming_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    service = DatabaseImportService(
      validateDatabaseUseCase: ValidateDatabaseUseCase(),
    );
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<List<String>> listing(String sub) async {
    final dir = Directory(p.join(tempDir.path, sub));
    if (!await dir.exists()) return const [];
    final entries = await dir.list(followLinks: false).toList();
    return entries.map((e) => p.basename(e.path)).toList()..sort();
  }

  test(
    'T006 AC-1: databases and keys listings are opaque and unlinkable',
    () async {
      final result = await service.importFromSelection(
        fileName: 'My Vault.kdbx',
        selectedBytes: validKdbxHeader,
      );
      final keyPath = await service.saveKeyFile(
        fileName: 'My Vault.key',
        keyFileBytes: Uint8List.fromList(List.filled(64, 7)),
      );

      final databases = await listing('databases');
      final keys = await listing('keys');
      expect(databases, hasLength(1));
      expect(keys, hasLength(1));

      for (final name in [...databases, ...keys]) {
        expect(name, matches(opaque));
        expect(name.toLowerCase(), isNot(contains('.kdbx')));
        expect(name.toLowerCase(), isNot(contains('.key')));
        expect(name.toLowerCase(), isNot(contains('vault')));
      }

      // Independent draws: the key name must share nothing with the database
      // name, so the association lives only in the encrypted metadata.
      expect(databases.single, isNot(keys.single));
      expect(p.basename(keyPath), keys.single);

      // The human-readable name survives where it is needed: the result the
      // registry record is built from.
      expect(result.fileName, 'My Vault.kdbx');
    },
  );

  test('T006b FR-1: importing copies; the original is never touched', () async {
    final original = File(p.join(tempDir.path, 'source', 'Mine.kdbx'));
    await original.create(recursive: true);
    await original.writeAsBytes(validKdbxHeader, flush: true);

    final result = await service.importFromSelection(
      fileName: 'Mine.kdbx',
      selectedPath: original.path,
    );

    expect(p.isWithin(tempDir.path, result.path), isTrue);
    expect(result.path, isNot(original.path));
    expect(await original.exists(), isTrue);
    expect(await original.readAsBytes(), validKdbxHeader);
  });

  test(
    'T006b FR-1: a selected key file is copied; the original is kept',
    () async {
      final original = File(p.join(tempDir.path, 'source', 'mine.key'));
      await original.create(recursive: true);
      await original.writeAsBytes(List.filled(64, 3), flush: true);

      final managed = await service.ensureManagedKeyFilePath(original.path);

      expect(managed, isNotNull);
      expect(managed, isNot(original.path));
      expect(p.basename(managed!), matches(opaque));
      expect(await original.exists(), isTrue);
      expect(await File(managed).readAsBytes(), List.filled(64, 3));
    },
  );
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
