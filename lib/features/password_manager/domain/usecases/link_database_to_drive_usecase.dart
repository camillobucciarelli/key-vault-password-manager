import '../models/database_sync_mapping.dart';
import '../repositories/database_sync_repository.dart';

class LinkDatabaseToDriveUseCase {
  LinkDatabaseToDriveUseCase(this._repository);

  final DatabaseSyncRepository _repository;

  Future<DatabaseSyncMapping> call({
    required String databasePath,
    String? remoteFileId,
    String? remoteFileName,
    String? remoteFolderId,
  }) {
    return _repository.linkDatabaseToDrive(
      databasePath: databasePath,
      remoteFileId: remoteFileId,
      remoteFileName: remoteFileName,
      remoteFolderId: remoteFolderId,
    );
  }
}
