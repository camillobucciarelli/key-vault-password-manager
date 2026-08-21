import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// spec-011 FR-4: the stored master password (the persistent biometric
/// credential) is scoped per database. Every operation takes the database id
/// and resolves its own keystore entry — there is no global entry any more.
abstract class SecureDataSource {
  Future<void> saveMasterPassword(String databaseId, String password);
  Future<String?> getMasterPassword(String databaseId);
  Future<void> clearMasterPassword(String databaseId);
}

class SecureDataSourceImpl implements SecureDataSource {
  /// spec-011 FR-6 (Slice 3): legacy global key, kept only so the one-time
  /// startup migration can delete it. No active path reads or writes it.
  static const legacyMasterPasswordKey = 'MASTER_PASSWORD';

  final FlutterSecureStorage secureStorage;

  SecureDataSourceImpl({required this.secureStorage});

  /// spec-011 FR-4: keystore key derived from the database id only — never
  /// from secret material. Distinct databases always map to distinct keys.
  static String masterPasswordKey(String databaseId) {
    final id = databaseId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(databaseId, 'databaseId', 'must not be empty');
    }
    return '$legacyMasterPasswordKey.$id';
  }

  @override
  Future<void> saveMasterPassword(String databaseId, String password) async {
    await secureStorage.write(
      key: masterPasswordKey(databaseId),
      value: password,
    );
  }

  @override
  Future<String?> getMasterPassword(String databaseId) async {
    return await secureStorage.read(key: masterPasswordKey(databaseId));
  }

  @override
  Future<void> clearMasterPassword(String databaseId) async {
    await secureStorage.delete(key: masterPasswordKey(databaseId));
  }
}
