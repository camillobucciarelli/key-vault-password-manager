abstract class DatabaseRepository {
  Future<String?> getSelectedDatabasePath();
  Future<void> saveSelectedDatabasePath(String path);
  Future<List<String>> getRecentDatabasePaths();
  Future<void> addRecentDatabasePath(String path);
  Future<void> removeRecentDatabasePath(String path);
  Future<String?> getSelectedKeyFilePath();
  Future<void> saveSelectedKeyFilePath(String? path);
  Future<bool> getBiometricProtectionEnabled();
  Future<void> setBiometricProtectionEnabled(bool enabled);
}
