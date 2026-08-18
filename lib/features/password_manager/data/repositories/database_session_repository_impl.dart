import '../../domain/repositories/database_session_repository.dart';
import '../datasources/local_data_source.dart';
import '../datasources/secure_data_source.dart';

/// Composes the existing local/secure data sources behind the
/// [DatabaseSessionRepository] domain port (C-7).
class DatabaseSessionRepositoryImpl implements DatabaseSessionRepository {
  DatabaseSessionRepositoryImpl({
    required this.localDataSource,
    required this.secureDataSource,
  });

  final LocalDataSource localDataSource;
  final SecureDataSource secureDataSource;

  @override
  Future<String?> getCachedKeyFilePath() =>
      localDataSource.getCachedKeyFilePath();

  @override
  Future<void> cacheKeyFilePath(String? path) =>
      localDataSource.cacheKeyFilePath(path);

  @override
  Future<void> saveMasterPassword(String password) =>
      secureDataSource.saveMasterPassword(password);

  @override
  Future<String?> getMasterPassword() => secureDataSource.getMasterPassword();

  @override
  Future<void> clearMasterPassword() => secureDataSource.clearMasterPassword();
}
