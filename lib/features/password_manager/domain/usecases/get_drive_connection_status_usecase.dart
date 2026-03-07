import '../repositories/database_sync_repository.dart';

class GetDriveConnectionStatusUseCase {
  GetDriveConnectionStatusUseCase(this._repository);

  final DatabaseSyncRepository _repository;

  Future<bool> call() {
    return _repository.isConnected();
  }
}
