import '../repositories/database_sync_repository.dart';

class SetDatabaseAutoSyncUseCase {
  SetDatabaseAutoSyncUseCase(this._repository);

  final DatabaseSyncRepository _repository;

  Future<void> call(String databasePath, bool enabled) {
    return _repository.setAutoSync(databasePath, enabled);
  }
}
