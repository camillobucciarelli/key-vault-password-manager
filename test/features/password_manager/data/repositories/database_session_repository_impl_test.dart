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

    test('composes local data source for key-file caching', () async {
      await repository.cacheKeyFilePath('/tmp/key.key');
      expect(await repository.getCachedKeyFilePath(), '/tmp/key.key');

      await repository.cacheKeyFilePath(null);
      expect(await repository.getCachedKeyFilePath(), isNull);
    });

    test('composes secure data source for the master password', () async {
      expect(await repository.getMasterPassword('db-1'), isNull);

      await repository.saveMasterPassword(
        'db-1',
        'kv-test-only-not-a-real-password',
      );
      expect(
        await repository.getMasterPassword('db-1'),
        'kv-test-only-not-a-real-password',
      );
      // FR-4: entries are keyed per database id.
      expect(await repository.getMasterPassword('db-2'), isNull);

      await repository.clearMasterPassword('db-1');
      expect(await repository.getMasterPassword('db-1'), isNull);
    });

    test('composes secure data source for the legacy global clear', () async {
      await repository.clearLegacyGlobalMasterPassword();
      expect(secureDataSource.legacyGlobalCleared, isTrue);
    });
  });
}

class _FakeLocalDataSource implements LocalDataSource {
  String? keyFilePath;
  bool autofillPromptSeen = false;

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
  final Map<String, String> passwords = {};
  bool legacyGlobalCleared = false;

  @override
  Future<void> clearMasterPassword(String databaseId) async {
    passwords.remove(databaseId);
  }

  @override
  Future<String?> getMasterPassword(String databaseId) async =>
      passwords[databaseId];

  @override
  Future<void> saveMasterPassword(String databaseId, String password) async {
    passwords[databaseId] = password;
  }

  @override
  Future<void> clearLegacyGlobalMasterPassword() async {
    legacyGlobalCleared = true;
  }
}
