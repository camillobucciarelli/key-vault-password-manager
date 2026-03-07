import '../repositories/database_repository.dart';

class GetSelectedDatabasePathUseCase {
  final DatabaseRepository repository;

  GetSelectedDatabasePathUseCase(this.repository);

  Future<String?> call() async {
    return await repository.getSelectedDatabasePath();
  }
}
