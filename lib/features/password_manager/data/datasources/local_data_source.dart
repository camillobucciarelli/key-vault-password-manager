import 'package:shared_preferences/shared_preferences.dart';

abstract class LocalDataSource {
  Future<String?> getCachedDatabasePath();
  Future<void> cacheDatabasePath(String path);
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
  static const keyFilePathKey = 'CACHED_KEY_FILE_PATH';
  static const biometricProtectionKey = 'BIOMETRIC_PROTECTION_ENABLED';
  static const autofillPromptSeenKey = 'AUTOFILL_PROMPT_SEEN';

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
