import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/local_data_source.dart';
import 'package:password_manager/features/password_manager/data/datasources/secure_data_source.dart';
import 'package:password_manager/features/password_manager/data/repositories/database_session_repository_impl.dart';

void main() {
  group('DatabaseSessionRepositoryImpl', () {
    late _FakeLocalDataSource localDataSource;
    late _FakeSecureDataSource secureDataSource;
    late DatabaseSessionRepositoryImpl repository;

    setUp(() {
      localDataSource = _FakeLocalDataSource();
      secureDataSource = _FakeSecureDataSource();
      repository = DatabaseSessionRepositoryImpl(
        localDataSource: localDataSource,
        secureDataSource: secureDataSource,
      );
    });

    test('composes local data source for path/key-file caching', () async {
      await repository.cacheDatabasePath('/tmp/vault.kdbx');
      expect(localDataSource.databasePath, '/tmp/vault.kdbx');

      await repository.cacheKeyFilePath('/tmp/key.key');
      expect(await repository.getCachedKeyFilePath(), '/tmp/key.key');

      await repository.cacheKeyFilePath(null);
      expect(await repository.getCachedKeyFilePath(), isNull);
    });

    test('composes secure data source for the master password', () async {
      expect(await repository.getMasterPassword(), isNull);

      await repository.saveMasterPassword('kv-test-only-not-a-real-password');
      expect(
        await repository.getMasterPassword(),
        'kv-test-only-not-a-real-password',
      );

      await repository.clearMasterPassword();
      expect(await repository.getMasterPassword(), isNull);
    });
  });
}

class _FakeLocalDataSource implements LocalDataSource {
  String? databasePath;
  String? keyFilePath;
  bool autofillPromptSeen = false;

  @override
  Future<void> cacheDatabasePath(String path) async {
    databasePath = path;
  }

  @override
  Future<String?> getCachedKeyFilePath() async => keyFilePath;

  @override
  Future<void> cacheKeyFilePath(String? path) async {
    keyFilePath = path;
  }

  @override
  Future<bool> getAutofillPromptSeen() async => autofillPromptSeen;

  @override
  Future<void> setAutofillPromptSeen(bool seen) async {
    autofillPromptSeen = seen;
  }
}

class _FakeSecureDataSource implements SecureDataSource {
  String? password;

  @override
  Future<void> clearMasterPassword() async {
    password = null;
  }

  @override
  Future<String?> getMasterPassword() async => password;

  @override
  Future<void> saveMasterPassword(String password) async {
    this.password = password;
  }
}
