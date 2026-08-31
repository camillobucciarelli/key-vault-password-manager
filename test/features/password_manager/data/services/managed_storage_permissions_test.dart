@TestOn('mac-os || linux')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/database_import_service.dart';
import 'package:password_manager/features/password_manager/data/services/safe_vault_file_writer.dart';
import 'package:password_manager/features/password_manager/domain/usecases/validate_database_usecase.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Spec 014 FR-7 / AC-3 (T012): freshly created databases, key files and
/// backups are owner-only. Asserted here for macOS/Linux; Windows records
/// the equivalent ACL outcome (no POSIX mode exists in dart:io there).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const validKdbxHeader = [0x03, 0xD9, 0xA2, 0x9A, 0x67, 0xFB, 0x4B, 0xB5];

  late Directory tempDir;
  late DatabaseImportService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('managed_perms_test_');
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

  Future<int> modeOf(String path) async {
    final result = await Process.run('stat', ['-f', '%Lp', path]);
    if (result.exitCode != 0) {
      final gnu = await Process.run('stat', ['-c', '%a', path]);
      return int.parse((gnu.stdout as String).trim(), radix: 8);
    }
    return int.parse((result.stdout as String).trim(), radix: 8);
  }

  test('a freshly created managed database is owner-only', () async {
    final result = await service.importFromSelection(
      fileName: 'Mine.kdbx',
      selectedBytes: validKdbxHeader,
    );
    expect(await modeOf(result.path), 0x180); // 0600
  });

  test('a freshly created managed key file is owner-only', () async {
    final keyPath = await service.saveKeyFile(
      fileName: 'mine.key',
      keyFileBytes: Uint8List.fromList(List.filled(64, 7)),
    );
    expect(await modeOf(keyPath), 0x180);
  });

  test('a backup of a pre-0600 vault is clamped to owner-only', () async {
    final vault = File(p.join(tempDir.path, 'loose.kdbx'));
    await vault.writeAsBytes(validKdbxHeader, flush: true);
    await Process.run('chmod', ['644', vault.path]);

    final backupPath = await SafeVaultFileWriter().createBackup(
      vault.path,
      operation: 'permissions test',
    );
    addTearDown(() => File(backupPath).delete());

    expect(
      await modeOf(backupPath),
      0x180,
      reason:
          'the backup mode floor is explicit, never inherited looser '
          'than owner-only (spec 014 FR-7)',
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
