import '../models/sync_conflict.dart';
import '../repositories/database_sync_repository.dart';

/// spec 010 T401: one manual/background sync round for a linked database.
/// Conflicts come back as [SyncNowConflict]; provider failures propagate as
/// `CloudStorageException` for presentation to map.
class SyncDatabaseNowUseCase {
  SyncDatabaseNowUseCase(this.repository);

  final DatabaseSyncRepository repository;

  Future<SyncNowResult> call(
    String databasePath, {
    SyncConflictResolution? resolution,
  }) {
    final path = databasePath.trim();
    if (path.isEmpty) {
      throw ArgumentError.value(
        databasePath,
        'databasePath',
        'must not be blank',
      );
    }
    return repository.syncNow(path, resolution: resolution);
  }
}
