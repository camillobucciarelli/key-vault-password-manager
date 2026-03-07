import '../models/drive_remote_file.dart';
import '../repositories/database_sync_repository.dart';

class ListDriveRemoteFilesUseCase {
  ListDriveRemoteFilesUseCase(this._repository);

  final DatabaseSyncRepository _repository;

  Future<List<DriveRemoteFile>> call() {
    return _repository.listRemoteFiles();
  }
}
