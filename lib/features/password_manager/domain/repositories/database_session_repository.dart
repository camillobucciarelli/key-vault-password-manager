/// C-7 domain port covering cached active/key path and stored
/// master-password operations. `DatabaseSessionRepositoryImpl` (data layer)
/// composes the existing local/secure data sources; the coordinator depends
/// only on this interface.
abstract class DatabaseSessionRepository {
  Future<void> cacheDatabasePath(String path);
  Future<String?> getCachedKeyFilePath();
  Future<void> cacheKeyFilePath(String? path);
  Future<void> saveMasterPassword(String password);
  Future<String?> getMasterPassword();
  Future<void> clearMasterPassword();
}
