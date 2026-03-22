abstract class DatabaseRepository {
  Future<void> saveSelectedDatabasePath(String path);
  Future<String?> getSelectedKeyFilePath();
  Future<void> saveSelectedKeyFilePath(String? path);
}
