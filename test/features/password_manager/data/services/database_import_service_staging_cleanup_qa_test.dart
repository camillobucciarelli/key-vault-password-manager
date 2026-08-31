import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/core/utils/mobile_file_storage.dart';
import 'package:password_manager/features/password_manager/data/services/database_import_service.dart';
import 'package:password_manager/features/password_manager/domain/errors/database_access_failure.dart';
import 'package:password_manager/features/password_manager/domain/usecases/validate_database_usecase.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// REGRESSION supplement to `database_import_service_staging_cleanup_test.dart`
/// (#46). That file holds the acceptance tests; this one holds the tests that
/// actually fail when the fix is reverted.
///
/// The developer's three tests are acceptance-only: they pass unchanged when
/// the fix is reverted, because `isPathInAppDirectory` is true for every path
/// the service produces *in their fixtures*. The tests here close that gap.
///
/// Which is which, so a future edit knows what it is allowed to weaken:
///   * `PRECONDITION:` / `FAIL-FIRST:` -- **discriminating**. The dangling
///     symlink on the staged name makes the old predicate answer false; with
///     the gate restored the staged entry survives and `FAIL-FIRST` fails.
///   * `a cleanup failure never masks ...` -- **discriminating** on the second
///     half of #46, the `try`/`catch` around the cleanup: without it the
///     caller sees a `FileSystemException` instead of the import failure.
///   * the two `the user-selected source is ...` tests -- **acceptance**. They
///     guard the boundary the unconditional delete must not cross (never touch
///     the user's own file), and pass either way.
///
/// Platform prerequisite: `Link.create`, which on Windows needs Developer Mode
/// or an elevated shell. Same caveat as the other QA symlink suites (#48).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const notAKdbx = [0x50, 0x4B, 0x03, 0x04, 0x00, 0x00, 0x00, 0x00];

  late Directory tempDir;
  late Directory databasesDir;
  late DatabaseImportService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('import_staging_qa_');
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

  Future<List<String>> managedEntries() async {
    if (!await databasesDir.exists()) {
      return const [];
    }
    final entries = await databasesDir.list(followLinks: false).toList();
    return entries.map((e) => p.basename(e.path)).toList()..sort();
  }

  test('PRECONDITION: a staged leaf resolving outside app storage is what the '
      'removed gate refused', () async {
    await databasesDir.create(recursive: true);
    final outside = Directory(p.join(tempDir.path, 'outside'));
    await outside.create(recursive: true);
    final victim = File(p.join(outside.path, 'bad.kdbx'));
    await victim.writeAsBytes(const [9, 9, 9, 9], flush: true);
    final linkPath = p.join(databasesDir.path, 'bad.kdbx');
    await Link(linkPath).create(victim.path);

    expect(
      await MobileFileStorage.isPathInAppDirectory(
        filePath: linkPath,
        subdirectory: 'databases',
      ),
      isFalse,
      reason:
          'This is the shape the old gate answered false to. If it ever '
          'becomes true, the reproducer below has stopped reproducing.',
    );
  });

  test('FAIL-FIRST: a staged entry whose leaf resolves outside app storage is '
      'still cleaned up', () async {
    // Pre-spec-014 shape: a *dangling* symlink planted at a predictable name
    // ('bad.kdbx') was invisible to `_buildUniquePath`, so the stager wrote
    // straight through it, creating the external target (#46). Since spec
    // 014 the at-rest name is an opaque random draw, so a planted link can
    // no longer be hit by name at all: the import stages its own opaque
    // file, fails validation, and cleans that file up. The planted link is
    // not ours and stays; the external victim is never created.
    await databasesDir.create(recursive: true);
    final outside = Directory(p.join(tempDir.path, 'outside'));
    await outside.create(recursive: true);
    final victimPath = p.join(outside.path, 'bad.kdbx');
    await Link(p.join(databasesDir.path, 'bad.kdbx')).create(victimPath);
    expect(await File(victimPath).exists(), isFalse);

    await expectLater(
      service.importFromSelection(
        fileName: 'bad.kdbx',
        selectedBytes: notAKdbx,
      ),
      throwsA(isA<InvalidDatabaseFileFailure>()),
    );

    expect(
      await managedEntries(),
      ['bad.kdbx'],
      reason:
          'Only the pre-existing planted link may remain: the staged '
          'opaque entry must not survive a failed import.',
    );
    expect(
      await File(victimPath).exists(),
      isFalse,
      reason: 'The external target must never be created through the link.',
    );
  });

  test(
    'a cleanup failure never masks the import failure the caller needs',
    () async {
      final failing = _CleanupExplodesImportService(
        validateDatabaseUseCase: ValidateDatabaseUseCase(),
      );

      await expectLater(
        failing.importFromSelection(
          fileName: 'bad.kdbx',
          selectedBytes: notAKdbx,
        ),
        throwsA(
          isA<InvalidDatabaseFileFailure>(),
          // Not the cleanup's FileSystemException: swallowing the wrong one
          // would surface a disk error where the UI expects "invalid file".
        ),
      );

      expect(failing.cleanupAttempted, isTrue);
    },
  );

  test(
    'the user-selected source file is never deleted on a failed import',
    () async {
      final sourcePath = p.join(tempDir.path, 'picked.kdbx');
      final source = File(sourcePath);
      await source.writeAsBytes(notAKdbx, flush: true);

      await expectLater(
        service.importFromSelection(
          fileName: 'picked.kdbx',
          selectedPath: sourcePath,
        ),
        throwsA(isA<InvalidDatabaseFileFailure>()),
      );

      expect(await source.exists(), isTrue);
      expect(await source.readAsBytes(), notAKdbx);
      expect(await managedEntries(), isEmpty);
    },
  );

  test('the user-selected source is not deleted even when it sits inside the '
      'managed databases directory', () async {
    // Hardest shape for an unconditional delete: the picked file already
    // lives in `Documents/databases`, so staging copies it to a uniquified
    // sibling. Only the copy is ours.
    await databasesDir.create(recursive: true);
    final sourcePath = p.join(databasesDir.path, 'picked.kdbx');
    await File(sourcePath).writeAsBytes(notAKdbx, flush: true);

    await expectLater(
      service.importFromSelection(
        fileName: 'picked.kdbx',
        selectedPath: sourcePath,
      ),
      throwsA(isA<InvalidDatabaseFileFailure>()),
    );

    expect(
      await File(sourcePath).exists(),
      isTrue,
      reason: 'The pre-existing entry is the user\'s, not the staged copy.',
    );
    expect(await managedEntries(), ['picked.kdbx']);
  });
}

class _CleanupExplodesImportService extends DatabaseImportService {
  _CleanupExplodesImportService({required super.validateDatabaseUseCase});

  bool cleanupAttempted = false;

  @override
  Future<void> deleteFile(String path) async {
    cleanupAttempted = true;
    throw const FileSystemException('cleanup exploded', 'qa');
  }
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
