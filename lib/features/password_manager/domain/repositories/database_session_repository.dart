/// C-7 domain port covering cached active/key path and stored
/// master-password operations. `DatabaseSessionRepositoryImpl` (data layer)
/// composes the existing local/secure data sources; the coordinator depends
/// only on this interface.
abstract class DatabaseSessionRepository {
  Future<String?> getCachedKeyFilePath();
  Future<void> cacheKeyFilePath(String? path);

  /// spec-011 FR-4: the biometric credential is keyed per database id.
  Future<void> saveMasterPassword(String databaseId, String password);
  Future<String?> getMasterPassword(String databaseId);
  Future<void> clearMasterPassword(String databaseId);

  /// spec-011 FR-6: delete the legacy global master-password entry once.
  Future<void> clearLegacyGlobalMasterPassword();
}
