import '../repositories/database_sync_repository.dart';

class ConnectGoogleAccountUseCase {
  ConnectGoogleAccountUseCase(this._repository);

  final DatabaseSyncRepository _repository;

  Future<void> call() {
    return _repository.connect();
  }
}
