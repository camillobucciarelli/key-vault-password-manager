import '../repositories/database_repository.dart';

class RemoveRecentDatabasePathUseCase {
  final DatabaseRepository repository;

  RemoveRecentDatabasePathUseCase(this.repository);

  Future<void> call(String path) async {
    return await repository.removeRecentDatabasePath(path);
  }
}
