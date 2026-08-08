import '../models/database_sync_mapping.dart';
import '../models/drive_account_summary.dart';
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
  Future<void> moveMappingPath({
    required String fromDatabasePath,
    required String toDatabasePath,
  });

  Future<DatabaseSyncMapping?> getMapping(String databasePath);

  /// spec-005 AC4: every local database's Drive mapping, used by the remote
  /// file picker to warn when a file is already linked elsewhere.
  Future<List<DatabaseSyncMapping>> getAllMappings();
  Future<void> setAutoSync(String databasePath, bool enabled);
  Future<List<DriveRemoteFile>> listRemoteFiles({String? query});
  Future<Uint8List> downloadRemoteFile(String fileId);

  /// C-2: the connected Google account's display label/email, or the
  /// desktop fallback when identity cannot be determined without expanding
  /// OAuth scopes.
  Future<DriveAccountSummary> getConnectedAccount();
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
