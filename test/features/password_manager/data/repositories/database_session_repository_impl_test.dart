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

    test('composes secure data source for the per-database master password '
        '(spec-011 FR-4)', () async {
      expect(await repository.getMasterPassword('db-a'), isNull);

      await repository.saveMasterPassword(
        'db-a',
        'kv-test-only-not-a-real-password',
      );
      expect(
        await repository.getMasterPassword('db-a'),
        'kv-test-only-not-a-real-password',
      );
      // Another database never sees this entry.
      expect(await repository.getMasterPassword('db-b'), isNull);

      await repository.clearMasterPassword('db-a');
      expect(await repository.getMasterPassword('db-a'), isNull);
    });
  });
}

class _FakeLocalDataSource implements LocalDataSource {
  String? keyFilePath;
  bool autofillPromptSeen = false;

  @override
  Future<bool> getAutofillPromptSeen() async => autofillPromptSeen;

  @override
  Future<void> setAutofillPromptSeen(bool seen) async {
    autofillPromptSeen = seen;
  }
}

class _FakeSecureDataSource implements SecureDataSource {
  final Map<String, String> metadataEntries = {};

  @override
  Future<String?> readMetadataKey() async =>
      metadataEntries['METADATA_ENCRYPTION_KEY'];

  @override
  Future<String> createMetadataKey() async {
    const key = 'dGVzdC1tZXRhZGF0YS1rZXktMzItYnl0ZXMtLS0tLS0=';
    metadataEntries['METADATA_ENCRYPTION_KEY'] = key;
    return key;
  }

  @override
  Future<void> deleteLegacyMasterPassword() async {}

  final Map<String, String> passwords = {};

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
}
