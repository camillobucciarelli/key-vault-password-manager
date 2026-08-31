import 'dart:convert';

import 'package:password_manager/features/password_manager/data/datasources/secure_data_source.dart';

/// In-memory [SecureDataSource] for tests: a working keystore with no
/// platform channel. Set [unavailable] to make every call throw, which is
/// the spec 014 FR-5 "secure store unavailable" shape.
class InMemorySecureDataSource implements SecureDataSource {
  final Map<String, String> entries = {};
  bool unavailable = false;

  void _check() {
    if (unavailable) {
      throw Exception('secure store unavailable (test)');
    }
  }

  @override
  Future<void> saveMasterPassword(String databaseId, String password) async {
    _check();
    entries['mp.$databaseId'] = password;
  }

  @override
  Future<String?> getMasterPassword(String databaseId) async {
    _check();
    return entries['mp.$databaseId'];
  }

  @override
  Future<void> clearMasterPassword(String databaseId) async {
    _check();
    entries.remove('mp.$databaseId');
  }

  @override
  Future<void> deleteLegacyMasterPassword() async {
    _check();
    entries.remove('MASTER_PASSWORD');
  }

  @override
  Future<String?> readMetadataKey() async {
    _check();
    return entries['METADATA_ENCRYPTION_KEY'];
  }

  @override
  Future<String> createMetadataKey() async {
    _check();
    final key = base64Encode(List<int>.generate(32, (i) => (i * 7 + 3) % 256));
    entries['METADATA_ENCRYPTION_KEY'] = key;
    return key;
  }
}
