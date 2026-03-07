import '../repositories/database_repository.dart';

class GetSelectedKeyFilePathUseCase {
  final DatabaseRepository repository;

  GetSelectedKeyFilePathUseCase(this.repository);

  Future<String?> call() async {
    return await repository.getSelectedKeyFilePath();
  }
}
