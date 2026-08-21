/// C-7 domain port covering cached active/key path and stored
/// master-password operations. `DatabaseSessionRepositoryImpl` (data layer)
/// composes the existing local/secure data sources; the coordinator depends
/// only on this interface.
///
/// spec-011 FR-4: master-password operations are scoped per database id —
/// the stored value is the persistent biometric credential of exactly one
/// database.
abstract class DatabaseSessionRepository {
  Future<String?> getCachedKeyFilePath();
  Future<void> cacheKeyFilePath(String? path);
  Future<void> saveMasterPassword(String databaseId, String password);
  Future<String?> getMasterPassword(String databaseId);
  Future<void> clearMasterPassword(String databaseId);
}
