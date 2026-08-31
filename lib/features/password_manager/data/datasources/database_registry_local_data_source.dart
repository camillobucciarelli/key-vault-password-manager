import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import '../../../../core/utils/managed_storage_root.dart';
import 'metadata_cipher.dart';
import 'secure_data_source.dart';

abstract class DatabaseRegistryLocalDataSource {
  Future<List<Map<String, dynamic>>> getRecords();
  Future<void> saveRecords(List<Map<String, dynamic>> records);
  Future<String?> getActiveDatabaseId();
  Future<void> saveActiveDatabaseId(String? databaseId);
}

class DatabaseRegistryLocalDataSourceImpl
    implements DatabaseRegistryLocalDataSource {
  DatabaseRegistryLocalDataSourceImpl({
    required this.sharedPreferences,
    required SecureDataSource secureDataSource,
  }) : _store = EncryptedMetadataStore(secureDataSource: secureDataSource);

  final EncryptedMetadataStore _store;

  static const _activeDatabaseIdKey = 'DATABASE_REGISTRY_ACTIVE_ID';
  static const _registrySubdirectory = 'metadata';
  static const _registryFileName = 'database_registry_records.json';

  final SharedPreferences sharedPreferences;

  @override
  Future<List<Map<String, dynamic>>> getRecords() async {
    final file = await _recordsFile();
    // spec 014 FR-4/FR-5: encrypted at rest; unreadable (absent file,
    // unavailable store, missing key, tampered bytes) reads as empty.
    final raw = await _store.readString(file);
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }

    return decoded
        .whereType<Map>()
        .map((item) => item.map((key, value) => MapEntry('$key', value)))
        .toList(growable: false);
  }

  @override
  Future<void> saveRecords(List<Map<String, dynamic>> records) async {
    final encoded = jsonEncode(records);
    final file = await _recordsFile();
    await _store.writeString(file, encoded);
  }

  @override
  Future<String?> getActiveDatabaseId() async {
    final value = sharedPreferences.getString(_activeDatabaseIdKey);
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value;
  }

  @override
  Future<void> saveActiveDatabaseId(String? databaseId) async {
    if (databaseId == null || databaseId.trim().isEmpty) {
      await sharedPreferences.remove(_activeDatabaseIdKey);
      return;
    }
    await sharedPreferences.setString(_activeDatabaseIdKey, databaseId);
  }

  Future<File> _recordsFile() async {
    final root = await ManagedStorageRoot.resolveDirectory();
    final directory = Directory(p.join(root.path, _registrySubdirectory));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(p.join(directory.path, _registryFileName));
  }
}
