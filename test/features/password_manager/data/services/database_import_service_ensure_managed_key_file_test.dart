import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/database_import_service.dart';
import 'package:password_manager/features/password_manager/domain/usecases/validate_database_usecase.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Regression coverage for the Copilot-flagged security bug: a source key
/// file that disappears (or is unreadable) between the caller's check and
/// `saveKeyFile`'s internal check must never result in a silently-created
/// empty key file being reported as a valid managed path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DatabaseImportService.ensureManagedKeyFilePath', () {
    late Directory tempDir;
    late DatabaseImportService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'ensure_managed_key_file_test_',
      );
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
      service = DatabaseImportService(
        validateDatabaseUseCase: ValidateDatabaseUseCase(),
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('existing source file is copied into managed storage', () async {
      final sourcePath = p.join(tempDir.path, 'source.key');
      const contents = 'real-key-bytes-not-empty';
      await File(sourcePath).writeAsString(contents);

      final result = await service.ensureManagedKeyFilePath(sourcePath);

      expect(result, isNotNull);
      expect(result, isNot(sourcePath));
      final managedFile = File(result!);
      expect(await managedFile.exists(), isTrue);
      expect(await managedFile.readAsString(), contents);
    });

    test('missing source file returns the original path unchanged and '
        'creates nothing in managed storage', () async {
      final missingPath = p.join(tempDir.path, 'does_not_exist.key');
      final keysDir = Directory(p.join(tempDir.path, 'keys'));

      final result = await service.ensureManagedKeyFilePath(missingPath);

      expect(result, missingPath);
      if (await keysDir.exists()) {
        final createdFiles = await keysDir.list().toList();
        expect(
          createdFiles,
          isEmpty,
          reason: 'No empty key file should ever be written.',
        );
      }
    });
  });
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.basePath);

  final String basePath;

  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;
}
