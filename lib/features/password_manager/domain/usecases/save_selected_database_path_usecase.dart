import '../repositories/database_repository.dart';

class SaveSelectedDatabasePathUseCase {
  final DatabaseRepository repository;

  SaveSelectedDatabasePathUseCase(this.repository);

  Future<void> call(String path) async {
    return await repository.saveSelectedDatabasePath(path);
  }
}
