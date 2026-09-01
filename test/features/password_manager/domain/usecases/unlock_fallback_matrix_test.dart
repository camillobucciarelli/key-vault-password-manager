import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kdbx/kdbx.dart';
import 'package:password_manager/features/password_manager/domain/errors/database_access_failure.dart';
import 'package:password_manager/features/password_manager/domain/usecases/unlock_database_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/vault_credentials.dart';
import 'package:path/path.dart' as p;

/// spec 015 FR-12 / AC-1, AC-7 (T017/T019): the shared fallback matrix.
/// Each credential combination that can be created can be unlocked, through
/// the same `composeVaultCredentials` composition on both sides.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final useCase = UnlockDatabaseUseCase();
  final keyBytes = Uint8List.fromList(List.generate(64, (i) => i * 3 % 256));

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('unlock_matrix_');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<({String dbPath, String keyPath})> createVault({
    required String password,
    required bool withKey,
  }) async {
    final credentials = composeVaultCredentials(
      password: password,
      keyFileBytes: withKey ? keyBytes : null,
    );
    final kdbx = KdbxFormat().create(credentials, 'Matrix');
    final bytes = await kdbx.save();
    final dbPath = p.join(tempDir.path, 'v.kdbx');
    await File(dbPath).writeAsBytes(bytes, flush: true);
    final keyPath = p.join(tempDir.path, 'v.key');
    if (withKey) {
      await File(keyPath).writeAsBytes(keyBytes, flush: true);
    }
    return (dbPath: dbPath, keyPath: keyPath);
  }

  test('password only: the password unlocks', () async {
    final vault = await createVault(
      password: 'kv-test-only-not-a-real-password',
      withKey: false,
    );
    await useCase(
      databasePath: vault.dbPath,
      password: 'kv-test-only-not-a-real-password',
      keyFilePath: null,
    );
  });

  test(
    'password + key: both are required — password alone is refused',
    () async {
      final vault = await createVault(
        password: 'kv-test-only-not-a-real-password',
        withKey: true,
      );
      await useCase(
        databasePath: vault.dbPath,
        password: 'kv-test-only-not-a-real-password',
        keyFilePath: vault.keyPath,
      );
      await expectLater(
        useCase(
          databasePath: vault.dbPath,
          password: 'kv-test-only-not-a-real-password',
          keyFilePath: null,
        ),
        throwsA(isA<InvalidCredentialsFailure>()),
      );
    },
  );

  test(
    'key only: selecting the key file unlocks with an empty password',
    () async {
      final vault = await createVault(password: '', withKey: true);
      await useCase(
        databasePath: vault.dbPath,
        password: '',
        keyFilePath: vault.keyPath,
      );
    },
  );

  test('key only: an empty password without the key is refused', () async {
    final vault = await createVault(password: '', withKey: true);
    await expectLater(
      useCase(databasePath: vault.dbPath, password: '', keyFilePath: null),
      throwsA(isA<InvalidCredentialsFailure>()),
    );
  });

  // spec 015 FR-15 (T024): no migration and no special-casing of existing
  // databases. The matrix above runs on vaults this test created from raw
  // bytes — indistinguishable from pre-existing ones — and the shared
  // credential path must not branch on any record identity or age.
  test('FR-15: the shared unlock path knows nothing about record identity, '
      'age or migration', () {
    final sources = [
      'lib/features/password_manager/domain/usecases/unlock_database_usecase.dart',
      'lib/features/password_manager/domain/usecases/vault_credentials.dart',
    ];
    for (final path in sources) {
      final code = File(path).readAsStringSync();
      for (final marker in ['sourceType', 'createdAt', 'migrat', 'legacy']) {
        expect(
          code.toLowerCase(),
          isNot(contains(marker.toLowerCase())),
          reason: '$path must not special-case databases by $marker',
        );
      }
    }
  });
}
