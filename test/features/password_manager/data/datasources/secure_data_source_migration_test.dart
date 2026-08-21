import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/secure_data_source.dart';

/// In-memory stand-in for the platform keystore. Only the members the data
/// source touches are implemented; anything else is an error.
class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> entries = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      entries.remove(key);
    } else {
      entries[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => entries[key];

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    entries.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  group('SecureDataSourceImpl.deleteLegacyMasterPassword (spec-011 FR-6)', () {
    late _FakeSecureStorage storage;
    late SecureDataSourceImpl dataSource;

    setUp(() {
      storage = _FakeSecureStorage();
      dataSource = SecureDataSourceImpl(secureStorage: storage);
    });

    test('deletes a pre-existing legacy global entry on first run', () async {
      storage.entries[SecureDataSourceImpl.legacyMasterPasswordKey] =
          'legacy-secret';

      await dataSource.deleteLegacyMasterPassword();

      expect(
        storage.entries.containsKey(
          SecureDataSourceImpl.legacyMasterPasswordKey,
        ),
        isFalse,
      );
    });

    test('is a no-op on a subsequent run with no legacy entry', () async {
      await dataSource.deleteLegacyMasterPassword();
      await dataSource.deleteLegacyMasterPassword();

      expect(storage.entries, isEmpty);
    });

    test('does not touch per-database entries', () async {
      storage.entries[SecureDataSourceImpl.legacyMasterPasswordKey] =
          'legacy-secret';
      final keyA = SecureDataSourceImpl.masterPasswordKey('db-a');
      final keyB = SecureDataSourceImpl.masterPasswordKey('db-b');
      storage.entries[keyA] = 'password-a';
      storage.entries[keyB] = 'password-b';

      await dataSource.deleteLegacyMasterPassword();

      expect(storage.entries, {keyA: 'password-a', keyB: 'password-b'});
    });
  });
}
