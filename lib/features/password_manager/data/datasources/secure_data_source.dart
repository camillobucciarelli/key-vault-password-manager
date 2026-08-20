import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistent store for the biometric-unlock credential (spec 011).
///
/// The master password reaches this store ONLY when the user enabled biometric
/// protection for a database (gated by the coordinator, FR-3). Each entry is
/// keyed per database id (FR-4), so a biometric unlock of database A can never
/// read database B's password.
abstract class SecureDataSource {
  Future<void> saveMasterPassword(String databaseId, String password);
  Future<String?> getMasterPassword(String databaseId);
  Future<void> clearMasterPassword(String databaseId);

  /// FR-6 migration: delete the pre-spec-011 global entry unconditionally.
  Future<void> clearLegacyGlobalMasterPassword();
}

class SecureDataSourceImpl implements SecureDataSource {
  /// Pre-spec-011 global key. Kept only so migration can delete it (FR-6);
  /// never written again.
  static const _legacyGlobalKey = 'MASTER_PASSWORD';
  static const _keyPrefix = 'MASTER_PASSWORD__';

  final FlutterSecureStorage secureStorage;

  SecureDataSourceImpl({required this.secureStorage});

  String _keyFor(String databaseId) => '$_keyPrefix$databaseId';

  @override
  Future<void> saveMasterPassword(String databaseId, String password) async {
    await secureStorage.write(key: _keyFor(databaseId), value: password);
  }

  @override
  Future<String?> getMasterPassword(String databaseId) async {
    return await secureStorage.read(key: _keyFor(databaseId));
  }

  @override
  Future<void> clearMasterPassword(String databaseId) async {
    await secureStorage.delete(key: _keyFor(databaseId));
  }

  @override
  Future<void> clearLegacyGlobalMasterPassword() async {
    await secureStorage.delete(key: _legacyGlobalKey);
  }
}
