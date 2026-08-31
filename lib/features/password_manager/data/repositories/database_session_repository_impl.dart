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
  Future<void> saveMasterPassword(String databaseId, String password) =>
      secureDataSource.saveMasterPassword(databaseId, password);

  @override
  Future<String?> getMasterPassword(String databaseId) =>
      secureDataSource.getMasterPassword(databaseId);

  @override
  Future<void> clearMasterPassword(String databaseId) =>
      secureDataSource.clearMasterPassword(databaseId);
}
