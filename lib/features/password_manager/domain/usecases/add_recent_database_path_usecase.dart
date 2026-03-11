import '../repositories/database_repository.dart';

class AddRecentDatabasePathUseCase {
  final DatabaseRepository repository;

  AddRecentDatabasePathUseCase(this.repository);

  Future<void> call(String path) async {
    return await repository.addRecentDatabasePath(path);
  }
}
