import '../../domain/repositories/database_repository.dart';
import '../datasources/local_data_source.dart';

class DatabaseRepositoryImpl implements DatabaseRepository {
  final LocalDataSource localDataSource;

  DatabaseRepositoryImpl({required this.localDataSource});

  @override
  Future<void> saveSelectedDatabasePath(String path) async {
    await localDataSource.cacheDatabasePath(path);
  }

  @override
  Future<String?> getSelectedKeyFilePath() async {
    return await localDataSource.getCachedKeyFilePath();
  }

  @override
  Future<void> saveSelectedKeyFilePath(String? path) async {
    await localDataSource.cacheKeyFilePath(path);
  }
}
