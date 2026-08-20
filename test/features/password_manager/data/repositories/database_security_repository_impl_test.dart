import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/database_security_local_data_source.dart';
import 'package:password_manager/features/password_manager/data/repositories/database_security_repository_impl.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// spec-011 FR-7: an absent biometric-protection flag must deserialise to false.
// Implicit consent to persist a secret is not consent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _FakePathProvider('/tmp');

  test('FR-7: absent biometricProtectionEnabled flag reads as false', () async {
    final local = _FakeLocalDataSource({
      'db-1': {
        'databaseId': 'db-1',
        // biometricProtectionEnabled intentionally absent (pre-spec-011 record).
      },
    });
    final repository = DatabaseSecurityRepositoryImpl(localDataSource: local);

    final profile = await repository.getProfile('db-1');

    expect(profile, isNotNull);
    expect(profile!.biometricProtectionEnabled, isFalse);
  });

  test('an explicit true flag is preserved', () async {
    final local = _FakeLocalDataSource({
      'db-1': {
        'databaseId': 'db-1',
        'biometricProtectionEnabled': true,
      },
    });
    final repository = DatabaseSecurityRepositoryImpl(localDataSource: local);

    final profile = await repository.getProfile('db-1');

    expect(profile!.biometricProtectionEnabled, isTrue);
  });
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.basePath);

  final String basePath;

  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;
}

class _FakeLocalDataSource implements DatabaseSecurityLocalDataSource {
  _FakeLocalDataSource(this.store);

  final Map<String, Map<String, dynamic>> store;

  @override
  Future<Map<String, dynamic>?> getProfile(String databaseId) async =>
      store[databaseId];

  @override
  Future<void> saveProfile(
    String databaseId,
    Map<String, dynamic> profile,
  ) async {
    store[databaseId] = profile;
  }

  @override
  Future<void> removeProfile(String databaseId) async {
    store.remove(databaseId);
  }
}
