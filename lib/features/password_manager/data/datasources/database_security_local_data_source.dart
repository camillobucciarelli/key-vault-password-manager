import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import '../../../../core/utils/managed_storage_root.dart';
import 'metadata_cipher.dart';
import 'secure_data_source.dart';

abstract class DatabaseSecurityLocalDataSource {
  Future<Map<String, dynamic>?> getProfile(String databaseId);
  Future<void> saveProfile(String databaseId, Map<String, dynamic> profile);
  Future<void> removeProfile(String databaseId);
}

class DatabaseSecurityLocalDataSourceImpl
    implements DatabaseSecurityLocalDataSource {
  DatabaseSecurityLocalDataSourceImpl({
    required SecureDataSource secureDataSource,
  }) : _store = EncryptedMetadataStore(secureDataSource: secureDataSource);

  final EncryptedMetadataStore _store;

  static const _securitySubdirectory = 'metadata';
  static const _profilesFileName = 'database_security_profiles.json';

  @override
  Future<Map<String, dynamic>?> getProfile(String databaseId) async {
    final profiles = await _loadProfiles();
    final value = profiles[databaseId];
    if (value == null) {
      return null;
    }
    return value.map((key, raw) => MapEntry(key, raw));
  }

  @override
  Future<void> saveProfile(
    String databaseId,
    Map<String, dynamic> profile,
  ) async {
    final profiles = await _loadProfiles();
    profiles[databaseId] = profile;
    await _persistProfiles(profiles);
  }

  @override
  Future<void> removeProfile(String databaseId) async {
    final profiles = await _loadProfiles();
    profiles.remove(databaseId);
    await _persistProfiles(profiles);
  }

  Future<Map<String, Map<String, dynamic>>> _loadProfiles() async {
    final file = await _profilesFile();
    final raw = await _store.readString(file);
    if (raw == null || raw.trim().isEmpty) {
      return <String, Map<String, dynamic>>{};
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return <String, Map<String, dynamic>>{};
    }

    final profiles = <String, Map<String, dynamic>>{};
    decoded.forEach((key, value) {
      if (value is Map) {
        profiles['$key'] = value.map(
          (mapKey, mapValue) => MapEntry('$mapKey', mapValue),
        );
      }
    });
    return profiles;
  }

  Future<void> _persistProfiles(
    Map<String, Map<String, dynamic>> profiles,
  ) async {
    final file = await _profilesFile();
    await _store.writeString(file, jsonEncode(profiles));
  }

  Future<File> _profilesFile() async {
    final root = await ManagedStorageRoot.resolveDirectory();
    final directory = Directory(p.join(root.path, _securitySubdirectory));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(p.join(directory.path, _profilesFileName));
  }
}
