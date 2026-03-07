import '../repositories/database_sync_repository.dart';

class DisconnectGoogleAccountUseCase {
  DisconnectGoogleAccountUseCase(this._repository);

  final DatabaseSyncRepository _repository;

  Future<void> call() {
    return _repository.disconnect();
  }
}
