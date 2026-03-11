import 'package:shared_preferences/shared_preferences.dart';

abstract class LocalDataSource {
  Future<String?> getCachedDatabasePath();
  Future<void> cacheDatabasePath(String path);
  Future<List<String>> getRecentDatabasePaths();
  Future<void> addRecentDatabasePath(String path);
  Future<void> removeRecentDatabasePath(String path);
  Future<String?> getCachedKeyFilePath();
  Future<void> cacheKeyFilePath(String? path);
  Future<bool> getBiometricProtectionEnabled();
  Future<void> setBiometricProtectionEnabled(bool enabled);
  Future<bool> getAutofillPromptSeen();
  Future<void> setAutofillPromptSeen(bool seen);
}

class LocalDataSourceImpl implements LocalDataSource {
  final SharedPreferences sharedPreferences;
  static const dbPathKey = 'CACHED_DATABASE_PATH';
  static const recentDbPathsKey = 'RECENT_DATABASE_PATHS';
  static const keyFilePathKey = 'CACHED_KEY_FILE_PATH';
  static const biometricProtectionKey = 'BIOMETRIC_PROTECTION_ENABLED';
  static const autofillPromptSeenKey = 'AUTOFILL_PROMPT_SEEN';
  static const maxRecentDatabases = 20;

  LocalDataSourceImpl({required this.sharedPreferences});

  @override
  Future<String?> getCachedDatabasePath() async {
    return sharedPreferences.getString(dbPathKey);
  }

  @override
  Future<void> cacheDatabasePath(String path) async {
    await sharedPreferences.setString(dbPathKey, path);
  }

  @override
  Future<List<String>> getRecentDatabasePaths() async {
    final values =
        sharedPreferences.getStringList(recentDbPathsKey) ?? const [];
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<void> addRecentDatabasePath(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      return;
    }

    final current = await getRecentDatabasePaths();
    final updated = <String>[normalized];
    for (final item in current) {
      if (item != normalized) {
        updated.add(item);
      }
      if (updated.length >= maxRecentDatabases) {
        break;
      }
    }

    await sharedPreferences.setStringList(recentDbPathsKey, updated);
  }

  @override
  Future<void> removeRecentDatabasePath(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      return;
    }

    final current = await getRecentDatabasePaths();
    final updated = current
        .where((item) => item != normalized)
        .toList(growable: false);
    await sharedPreferences.setStringList(recentDbPathsKey, updated);
  }

  @override
  Future<String?> getCachedKeyFilePath() async {
    final value = sharedPreferences.getString(keyFilePathKey);
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value;
  }

  @override
  Future<void> cacheKeyFilePath(String? path) async {
    if (path == null || path.trim().isEmpty) {
      await sharedPreferences.remove(keyFilePathKey);
      return;
    }
    await sharedPreferences.setString(keyFilePathKey, path);
  }

  @override
  Future<bool> getBiometricProtectionEnabled() async {
    return sharedPreferences.getBool(biometricProtectionKey) ?? true;
  }

  @override
  Future<void> setBiometricProtectionEnabled(bool enabled) async {
    await sharedPreferences.setBool(biometricProtectionKey, enabled);
  }

  @override
  Future<bool> getAutofillPromptSeen() async {
    return sharedPreferences.getBool(autofillPromptSeenKey) ?? false;
  }

  @override
  Future<void> setAutofillPromptSeen(bool seen) async {
    await sharedPreferences.setBool(autofillPromptSeenKey, seen);
  }
}
