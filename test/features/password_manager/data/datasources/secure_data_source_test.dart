import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:password_manager/features/password_manager/data/datasources/secure_data_source.dart';

// spec-011 FR-4 (per-database key) and FR-6 (legacy global clear).
void main() {
  late _InMemorySecureStorage storage;
  late SecureDataSourceImpl dataSource;

  setUp(() {
    storage = _InMemorySecureStorage();
    dataSource = SecureDataSourceImpl(secureStorage: storage);
  });

  test('FR-4: entries are keyed per database id', () async {
    await dataSource.saveMasterPassword('db-a', 'pw-a');
    await dataSource.saveMasterPassword('db-b', 'pw-b');

    expect(await dataSource.getMasterPassword('db-a'), 'pw-a');
    expect(await dataSource.getMasterPassword('db-b'), 'pw-b');

    await dataSource.clearMasterPassword('db-a');
    expect(await dataSource.getMasterPassword('db-a'), isNull);
    expect(await dataSource.getMasterPassword('db-b'), 'pw-b');
  });

  test('FR-4: keys are namespaced, not the bare id or legacy global', () async {
    await dataSource.saveMasterPassword('db-a', 'pw-a');

    expect(storage.store.keys, contains('MASTER_PASSWORD__db-a'));
    expect(storage.store.keys, isNot(contains('MASTER_PASSWORD')));
    expect(storage.store.keys, isNot(contains('db-a')));
  });

  test('FR-6: clearLegacyGlobalMasterPassword deletes only the legacy key',
      () async {
    storage.store['MASTER_PASSWORD'] = 'legacy-plaintext';
    await dataSource.saveMasterPassword('db-a', 'pw-a');

    await dataSource.clearLegacyGlobalMasterPassword();

    expect(storage.store.containsKey('MASTER_PASSWORD'), isFalse);
    // The per-database entry is untouched.
    expect(await dataSource.getMasterPassword('db-a'), 'pw-a');
  });
}

class _InMemorySecureStorage implements FlutterSecureStorage {
  final Map<String, String> store = {};

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
      store.remove(key);
    } else {
      store[key] = value;
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
  }) async =>
      store[key];

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
    store.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
