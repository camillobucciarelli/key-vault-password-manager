import '../models/database_sync_mapping.dart';
import '../models/drive_remote_file.dart';
import '../models/sync_conflict.dart';
import 'dart:typed_data';

sealed class SyncNowResult {
  const SyncNowResult();
}

class SyncNowSuccess extends SyncNowResult {
  const SyncNowSuccess();
}

class SyncNowConflict extends SyncNowResult {
  const SyncNowConflict(this.conflict);

  final SyncConflict conflict;
}

abstract class DatabaseSyncRepository {
  Future<bool> isConnected();
  Future<void> connect();
  Future<void> disconnect();
  Future<void> removeMapping(String databasePath);

  Future<DatabaseSyncMapping?> getMapping(String databasePath);
  Future<void> setAutoSync(String databasePath, bool enabled);
  Future<List<DriveRemoteFile>> listRemoteFiles({String? query});
  Future<Uint8List> downloadRemoteFile(String fileId);
  Future<DatabaseSyncMapping> linkDatabaseToDrive({
    required String databasePath,
    String? remoteFileId,
    String? remoteFileName,
  });

  Future<SyncNowResult> syncNow(
    String databasePath, {
    SyncConflictResolution? resolution,
  });
}
