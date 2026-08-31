import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/database_import_service.dart';
import 'package:password_manager/features/password_manager/domain/errors/database_access_failure.dart';
import 'package:password_manager/features/password_manager/domain/usecases/validate_database_usecase.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// ACCEPTANCE coverage for #46: a failed import must not leave the file it
/// staged behind in `Documents/databases`.
///
/// **These tests do not discriminate on the fix.** All three pass unchanged
/// with the #46 cleanup gate restored, because `isPathInAppDirectory` is true
/// for every path the service produces in these fixtures. They pin the
/// user-visible rule, not the defect. The fail-first reproducer lives in
/// `database_import_service_staging_cleanup_qa_test.dart` -- change the
/// cleanup path and run that one to know whether you broke anything.
///
/// `importFromSelection` copies the selection into managed storage *before*
/// validating it. The cleanup on the failure path used to be gated on
/// `MobileFileStorage.isPathInAppDirectory`; when that predicate returned
/// false the staged file was simply never deleted. The predicate can only be
/// false for a path the service could not have produced, so the gate bought
/// nothing and had one failure mode of its own: leaving a `.kdbx`-sized file
/// in `Documents/databases` that nothing ever collects.
///
/// The reason the acceptance/regression split exists at all: #41 hardened
/// `isPathInAppDirectory` to resolve symlinks (and, through
/// `resolveForComparison`, case) on both sides, so falsifying the predicate
/// now takes a deliberately adversarial fixture -- a dangling symlink on the
/// staged name -- rather than any ordinary import shape.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 8-byte KDBX header: signature 1 0x9AA2D903, signature 2 0xB54BFB67,
  // little-endian. Anything else is rejected as `invalidStructure`.
  const validKdbxHeader = [0x03, 0xD9, 0xA2, 0x9A, 0x67, 0xFB, 0x4B, 0xB5];
  const notAKdbx = [0x50, 0x4B, 0x03, 0x04, 0x00, 0x00, 0x00, 0x00];

  group('ACCEPTANCE: importFromSelection staging cleanup', () {
    late Directory tempDir;
    late Directory databasesDir;
    late DatabaseImportService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('import_staging_test_');
      databasesDir = Directory(p.join(tempDir.path, 'databases'));
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

    Future<List<String>> managedDatabaseFiles() async {
      if (!await databasesDir.exists()) {
        return const [];
      }
      final entries = await databasesDir.list().toList();
      return entries.map((e) => p.basename(e.path)).toList();
    }

    test(
      'an invalid selection staged from bytes leaves nothing behind',
      () async {
        await expectLater(
          service.importFromSelection(
            fileName: 'bad.kdbx',
            selectedBytes: notAKdbx,
          ),
          throwsA(isA<InvalidDatabaseFileFailure>()),
        );

        expect(await managedDatabaseFiles(), isEmpty);
      },
    );

    test('an invalid selection staged from a picked path leaves nothing '
        'behind', () async {
      final sourcePath = p.join(tempDir.path, 'picked.kdbx');
      await File(sourcePath).writeAsBytes(notAKdbx, flush: true);

      await expectLater(
        service.importFromSelection(
          fileName: 'picked.kdbx',
          selectedPath: sourcePath,
        ),
        throwsA(isA<InvalidDatabaseFileFailure>()),
      );

      expect(await managedDatabaseFiles(), isEmpty);
      expect(
        await File(sourcePath).exists(),
        isTrue,
        reason: 'Only the staged copy is ours to delete, never the source.',
      );
    });

    test('a valid selection is kept in managed storage', () async {
      final result = await service.importFromSelection(
        fileName: 'good.kdbx',
        selectedBytes: validKdbxHeader,
      );

      expect(p.isWithin(databasesDir.path, result.path), isTrue);
      // spec 014 FR-3: the at-rest name is opaque — 32 lowercase hex chars,
      // no extension, unrelated to the human-readable name.
      final files = await managedDatabaseFiles();
      expect(files, hasLength(1));
      expect(files.single, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(result.fileName, 'good.kdbx');
    });
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
