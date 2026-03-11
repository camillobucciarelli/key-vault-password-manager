import '../repositories/database_repository.dart';

class GetRecentDatabasePathsUseCase {
  final DatabaseRepository repository;

  GetRecentDatabasePathsUseCase(this.repository);

  Future<List<String>> call() async {
    return await repository.getRecentDatabasePaths();
  }
}
