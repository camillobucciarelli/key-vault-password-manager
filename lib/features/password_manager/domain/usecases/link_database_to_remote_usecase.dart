import '../models/database_sync_mapping.dart';
import '../repositories/database_sync_repository.dart';

/// spec 010 T401: links a local database to a remote file, or creates a new
/// remote file when no id is given. The "link existing vs create new"
/// decision lives here: a blank [remoteFileId] means create, matching the
/// orchestrator's contract, so callers never pass `''` by accident.
class LinkDatabaseToRemoteUseCase {
  LinkDatabaseToRemoteUseCase(this.repository);

  final DatabaseSyncRepository repository;

  Future<DatabaseSyncMapping> call({
    required String databasePath,
    String? remoteFileId,
    String? remoteFileName,
  }) {
    final path = databasePath.trim();
    if (path.isEmpty) {
      throw ArgumentError.value(
        databasePath,
        'databasePath',
        'must not be blank',
      );
    }
    return repository.linkDatabaseToRemote(
      databasePath: path,
      remoteFileId: _blankToNull(remoteFileId),
      remoteFileName: _blankToNull(remoteFileName),
    );
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
