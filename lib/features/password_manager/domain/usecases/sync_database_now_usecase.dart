import '../models/sync_conflict.dart';
import '../repositories/database_sync_repository.dart';

class SyncDatabaseNowUseCase {
  SyncDatabaseNowUseCase(this._repository);

  final DatabaseSyncRepository _repository;

  Future<SyncNowResult> call(
    String databasePath, {
    SyncConflictResolution? resolution,
  }) {
    return _repository.syncNow(databasePath, resolution: resolution);
  }
}
