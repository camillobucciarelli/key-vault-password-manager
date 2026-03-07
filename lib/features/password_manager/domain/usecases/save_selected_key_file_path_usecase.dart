import '../repositories/database_repository.dart';

class SaveSelectedKeyFilePathUseCase {
  final DatabaseRepository repository;

  SaveSelectedKeyFilePathUseCase(this.repository);

  Future<void> call(String? path) async {
    return await repository.saveSelectedKeyFilePath(path);
  }
}
