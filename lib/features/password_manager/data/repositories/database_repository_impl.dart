import '../../domain/repositories/database_repository.dart';
import '../datasources/local_data_source.dart';

class DatabaseRepositoryImpl implements DatabaseRepository {
  final LocalDataSource localDataSource;

  DatabaseRepositoryImpl({required this.localDataSource});

  @override
  Future<String?> getSelectedDatabasePath() async {
    return await localDataSource.getCachedDatabasePath();
  }

  @override
  Future<void> saveSelectedDatabasePath(String path) async {
    await localDataSource.cacheDatabasePath(path);
  }

  @override
  Future<List<String>> getRecentDatabasePaths() async {
    return await localDataSource.getRecentDatabasePaths();
  }

  @override
  Future<void> addRecentDatabasePath(String path) async {
    await localDataSource.addRecentDatabasePath(path);
  }

  @override
  Future<void> removeRecentDatabasePath(String path) async {
    await localDataSource.removeRecentDatabasePath(path);
  }

  @override
  Future<String?> getSelectedKeyFilePath() async {
    return await localDataSource.getCachedKeyFilePath();
  }

  @override
  Future<void> saveSelectedKeyFilePath(String? path) async {
    await localDataSource.cacheKeyFilePath(path);
  }

  @override
  Future<bool> getBiometricProtectionEnabled() async {
    return await localDataSource.getBiometricProtectionEnabled();
  }

  @override
  Future<void> setBiometricProtectionEnabled(bool enabled) async {
    await localDataSource.setBiometricProtectionEnabled(enabled);
  }
}
