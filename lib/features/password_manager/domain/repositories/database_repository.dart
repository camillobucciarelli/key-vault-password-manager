abstract class DatabaseRepository {
  Future<String?> getSelectedDatabasePath();
  Future<void> saveSelectedDatabasePath(String path);
  Future<String?> getSelectedKeyFilePath();
  Future<void> saveSelectedKeyFilePath(String? path);
  Future<bool> getBiometricProtectionEnabled();
  Future<void> setBiometricProtectionEnabled(bool enabled);
}
