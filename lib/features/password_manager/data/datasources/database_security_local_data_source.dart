import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract class DatabaseSecurityLocalDataSource {
  Future<Map<String, dynamic>?> getProfile(String databaseId);
  Future<void> saveProfile(String databaseId, Map<String, dynamic> profile);
  Future<void> removeProfile(String databaseId);
}

class DatabaseSecurityLocalDataSourceImpl
    implements DatabaseSecurityLocalDataSource {
  DatabaseSecurityLocalDataSourceImpl();

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
    if (!await file.exists()) {
      return <String, Map<String, dynamic>>{};
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
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
    await file.writeAsString(jsonEncode(profiles), flush: true);
  }

  Future<File> _profilesFile() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, _securitySubdirectory));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(p.join(directory.path, _profilesFileName));
  }
}
