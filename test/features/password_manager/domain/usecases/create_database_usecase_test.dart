// spec-003 C-5/T3: CreateDatabaseUseCase success + partial-output rollback
// through a fake DatabaseFileRepository port (no real disk I/O needed).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/models/database_import_result.dart';
import 'package:password_manager/features/password_manager/domain/models/database_import_transaction.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_file_repository.dart';
import 'package:password_manager/features/password_manager/domain/usecases/create_database_usecase.dart';

void main() {
  group('CreateDatabaseUseCase', () {
    late _FakeDatabaseFileRepository repository;
    late CreateDatabaseUseCase useCase;

    setUp(() {
      repository = _FakeDatabaseFileRepository();
      useCase = CreateDatabaseUseCase(databaseFileRepository: repository);
    });

    test('returns null when the destination picker is cancelled', () async {
      repository.resolveOutputFilePathResult = null;

      final result = await useCase(
        const CreateDatabaseRequest(
          databaseFileName: 'vault',
          password: 'kv-test-only-not-a-real-password',
        ),
      );

      expect(result, isNull);
      expect(repository.createDatabaseCalls, 0);
    });

    test('creates a database and returns its path/hash', () async {
      repository.resolveOutputFilePathResult = 'vault.kdbx';
      repository.createDatabaseResult = '/managed/vault.kdbx';
      repository.hashFileResult = 'hash-123';

      final result = await useCase(
        const CreateDatabaseRequest(
          databaseFileName: 'vault',
          password: 'kv-test-only-not-a-real-password',
        ),
      );

      expect(result, isNotNull);
      expect(result!.databasePath, '/managed/vault.kdbx');
      expect(result.fileHash, 'hash-123');
      expect(repository.createDatabaseCalls, 1);
    });

    test(
      'rolls back (deletes) partial output when post-create hashing fails',
      () async {
        repository.resolveOutputFilePathResult = 'vault.kdbx';
        repository.createDatabaseResult = '/managed/vault.kdbx';
        repository.hashFileError = Exception('disk full');

        await expectLater(
          useCase(
            const CreateDatabaseRequest(
              databaseFileName: 'vault',
              password: 'kv-test-only-not-a-real-password',
            ),
          ),
          throwsException,
        );

        expect(repository.deletedPaths, contains('/managed/vault.kdbx'));
      },
    );

    // Key-file preparation (`generateKeyFile: true`) is intentionally
    // skipped under `FLUTTER_TEST` (see `CreateDatabaseUseCase._prepareKeyFilePath`
    // callers), the same guard the pre-existing coordinator used to avoid
    // ever triggering a real file picker during automated tests. There is
    // no test exercising that specific branch at any level — it is a known
    // gap, not something covered elsewhere.
    //
    // `database_session_coordinator_test.dart`'s
    // "createNewDatabase failure cleanup" group covers a different
    // concern: that a failing/throwing `CreateDatabaseUseCase` leaves no
    // further coordinator-level mutation (prior active database/session
    // credentials unchanged), complementing this file's proof that the use
    // case itself deletes its own partial file output.
  });
}

class _FakeDatabaseFileRepository implements DatabaseFileRepository {
  String? resolveOutputFilePathResult = 'vault.kdbx';
  String createDatabaseResult = '/managed/vault.kdbx';
  String hashFileResult = 'hash';
  Object? hashFileError;
  String? saveKeyFileResult;
  int createDatabaseCalls = 0;
  int? savedKeyFileBytesLength;
  final List<String> deletedPaths = [];

  @override
  Future<String> createDatabase({
    required String outputFile,
    required Uint8List databaseBytes,
  }) async {
    createDatabaseCalls += 1;
    return createDatabaseResult;
  }

  @override
  Future<void> deleteFile(String path) async {
    deletedPaths.add(path);
  }

  @override
  Future<void> copyFile({
    required String sourcePath,
    required String targetPath,
  }) async {
    throw UnimplementedError('copyFile is not exercised by this use case');
  }

  @override
  Future<void> renameFile({
    required String sourcePath,
    required String targetPath,
  }) async {
    throw UnimplementedError('renameFile is not exercised by this use case');
  }

  @override
  Future<String?> ensureManagedKeyFilePath(String? keyFilePath) async =>
      keyFilePath;

  @override
  Future<String> hashFile(String path) async {
    if (hashFileError != null) {
      throw hashFileError!;
    }
    return hashFileResult;
  }

  @override
  Future<Uint8List> readKeyFileBytes(String keyFilePath) async => Uint8List(0);

  @override
  Future<String> saveKeyFile({
    required String fileName,
    required Uint8List keyFileBytes,
    String? selectedPath,
  }) async {
    savedKeyFileBytesLength = keyFileBytes.length;
    return saveKeyFileResult ?? '/managed/keys/$fileName';
  }

  @override
  Future<String?> resolveOutputFilePath(String preferredFileName) async =>
      resolveOutputFilePathResult;

  // Unused by CreateDatabaseUseCase; not exercised by these tests.
  @override
  Future<DatabaseFileCommit> commitStagedDatabase(
    StagedDatabaseImport staged, {
    String? targetPath,
  }) => throw UnimplementedError();

  @override
  Future<void> discardStagedDatabase(StagedDatabaseImport staged) =>
      throw UnimplementedError();

  @override
  Future<bool> fileExists(String path) => throw UnimplementedError();

  @override
  Future<void> finalizeDatabaseCommit(DatabaseFileCommit commit) =>
      throw UnimplementedError();

  @override
  Future<bool> keyFileExists(String keyFilePath) => throw UnimplementedError();

  @override
  Future<String> managedDatabasePath(String fileName) =>
      throw UnimplementedError();

  @override
  Future<DatabaseImportResult> openExistingPath(String path) =>
      throw UnimplementedError();

  @override
  Future<void> rollbackDatabaseCommit(DatabaseFileCommit commit) =>
      throw UnimplementedError();

  @override
  Future<StagedDatabaseImport> stageDriveDownload({
    required String fileName,
    required Uint8List bytes,
    required String remoteFileId,
  }) => throw UnimplementedError();

  @override
  Future<StagedDatabaseImport> stageLocalSelection({
    required String fileName,
    String? selectedPath,
    List<int>? selectedBytes,
  }) => throw UnimplementedError();
}
