import '../models/drive_remote_folder.dart';
import '../repositories/database_sync_repository.dart';

class ListDriveRemoteFoldersUseCase {
  ListDriveRemoteFoldersUseCase(this._repository);

  final DatabaseSyncRepository _repository;

  Future<List<DriveRemoteFolder>> call({String? query}) {
    return _repository.listRemoteFolders(query: query);
  }
}
