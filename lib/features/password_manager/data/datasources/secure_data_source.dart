import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// spec-011 FR-4: the stored master password (the persistent biometric
/// credential) is scoped per database. Every operation takes the database id
/// and resolves its own keystore entry — there is no global entry any more.
abstract class SecureDataSource {
  Future<void> saveMasterPassword(String databaseId, String password);
  Future<String?> getMasterPassword(String databaseId);
  Future<void> clearMasterPassword(String databaseId);

  /// spec-011 FR-6: deletes the legacy global `'MASTER_PASSWORD'` entry.
  /// Called unconditionally at every startup — deleting an absent key is a
  /// no-op, so no persisted "migrated" flag is needed. The value is never
  /// copied to a per-database entry because it cannot be attributed to one.
  Future<void> deleteLegacyMasterPassword();

  /// spec 014 FR-4: the base64 metadata-file encryption key, or `null` when
  /// the store answers but holds none. Throws when the secure store is
  /// unavailable — callers treat that as the FR-5 empty state and never
  /// fall back to plaintext. No biometric gate: this key only lists
  /// databases, it never unlocks one.
  Future<String?> readMetadataKey();

  /// Mints, stores and returns a fresh metadata key. Callers must only
  /// invoke this when no ciphertext exists yet (spec 014 safety gate 4);
  /// [EncryptedMetadataStore] is the one enforcing that.
  Future<String> createMetadataKey();
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

  @override
  Future<void> deleteLegacyMasterPassword() async {
    await secureStorage.delete(key: legacyMasterPasswordKey);
  }

  /// spec 014 FR-4: single well-known entry; never derived from any secret.
  static const metadataKeyKey = 'METADATA_ENCRYPTION_KEY';

  @override
  Future<String?> readMetadataKey() {
    return secureStorage.read(key: metadataKeyKey);
  }

  @override
  Future<String> createMetadataKey() async {
    final random = Random.secure();
    final key = base64Encode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    await secureStorage.write(key: metadataKeyKey, value: key);
    return key;
  }
}
