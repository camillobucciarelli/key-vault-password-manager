// spec-003 C-3: maps concrete `kdbx` package exceptions and absent-file
// cases to typed `DatabaseAccessFailure`s. Never confuses "corrupted" with
// "wrong password".
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kdbx/kdbx.dart';
import 'package:password_manager/features/password_manager/domain/errors/database_access_failure.dart';
import 'package:password_manager/features/password_manager/domain/usecases/unlock_database_usecase.dart';

void main() {
  group('UnlockDatabaseUseCase', () {
    late Directory tempDir;
    late UnlockDatabaseUseCase useCase;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('unlock_usecase_test_');
      useCase = UnlockDatabaseUseCase();
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    Future<String> writeValidDatabase(String password) async {
      final credentials = Credentials(ProtectedValue.fromString(password));
      final kdbx = KdbxFormat().create(credentials, 'Test Database');
      final bytes = await kdbx.save();
      final path = '${tempDir.path}/vault.kdbx';
      await File(path).writeAsBytes(bytes, flush: true);
      return path;
    }

    test('absent database file maps to DatabaseFileMissingFailure', () async {
      await expectLater(
        useCase(
          databasePath: '${tempDir.path}/missing.kdbx',
          password: 'anything',
        ),
        throwsA(isA<DatabaseFileMissingFailure>()),
      );
    });

    test('absent key file maps to KeyFileMissingFailure', () async {
      final path = await writeValidDatabase('kv-test-only-not-a-real-password');
      await expectLater(
        useCase(
          databasePath: path,
          password: 'kv-test-only-not-a-real-password',
          keyFilePath: '${tempDir.path}/missing.key',
        ),
        throwsA(isA<KeyFileMissingFailure>()),
      );
    });

    test('wrong password on a structurally valid KDBX maps to '
        'InvalidCredentialsFailure, never CorruptDatabaseFailure', () async {
      final path = await writeValidDatabase('kv-test-only-not-a-real-password');
      await expectLater(
        useCase(databasePath: path, password: 'wrong-password'),
        throwsA(isA<InvalidCredentialsFailure>()),
      );
    });

    test(
      'a KDBX-magic file with corrupted body maps to CorruptDatabaseFailure',
      () async {
        final validPath = await writeValidDatabase(
          'kv-test-only-not-a-real-password',
        );
        final validBytes = await File(validPath).readAsBytes();
        // Keep the KDBX magic header (first 12 bytes cover signature +
        // version) but corrupt everything after it so the package fails
        // while parsing structure, not while checking the key.
        final corrupted = Uint8List.fromList(validBytes);
        for (var i = 64; i < corrupted.length; i++) {
          corrupted[i] = 0xFF;
        }
        final corruptPath = '${tempDir.path}/corrupt.kdbx';
        await File(corruptPath).writeAsBytes(corrupted, flush: true);

        await expectLater(
          useCase(
            databasePath: corruptPath,
            password: 'kv-test-only-not-a-real-password',
          ),
          throwsA(isA<CorruptDatabaseFailure>()),
        );
      },
    );

    test('correct credentials succeed without throwing', () async {
      final path = await writeValidDatabase('kv-test-only-not-a-real-password');
      await useCase(
        databasePath: path,
        password: 'kv-test-only-not-a-real-password',
      );
    });
  });
}
