import '../../domain/models/database_sync_mapping.dart';
import '../../domain/models/drive_remote_file.dart';
import '../../domain/models/sync_conflict.dart';
import '../../domain/repositories/database_sync_repository.dart';
import 'dart:typed_data';
import '../services/database_sync_orchestrator.dart';
import '../services/drive_auth_service.dart';

class DatabaseSyncRepositoryImpl implements DatabaseSyncRepository {
  DatabaseSyncRepositoryImpl({
    required DriveAuthService driveAuthService,
    required DatabaseSyncOrchestrator databaseSyncOrchestrator,
  }) : _driveAuthService = driveAuthService,
       _databaseSyncOrchestrator = databaseSyncOrchestrator;

  final DriveAuthService _driveAuthService;
  final DatabaseSyncOrchestrator _databaseSyncOrchestrator;

  @override
  Future<void> connect() {
    return _driveAuthService.connect();
  }

  @override
  Future<void> disconnect() {
    return _driveAuthService.disconnect();
  }

  @override
  Future<void> removeMapping(String databasePath) {
    return _databaseSyncOrchestrator.removeMapping(databasePath);
  }

  @override
  Future<DatabaseSyncMapping?> getMapping(String databasePath) {
    return _databaseSyncOrchestrator.getMapping(databasePath);
  }

  @override
  Future<bool> isConnected() {
    return _driveAuthService.isConnected();
  }

  @override
  Future<DatabaseSyncMapping> linkDatabaseToDrive({
    required String databasePath,
    String? remoteFileId,
    String? remoteFileName,
  }) {
    return _databaseSyncOrchestrator.linkDatabaseToDrive(
      databasePath: databasePath,
      remoteFileId: remoteFileId,
      remoteFileName: remoteFileName,
    );
  }

  @override
  Future<List<DriveRemoteFile>> listRemoteFiles({String? query}) {
    return _databaseSyncOrchestrator.listRemoteFiles(query: query);
  }

  @override
  Future<Uint8List> downloadRemoteFile(String fileId) {
    return _databaseSyncOrchestrator.downloadRemoteFile(fileId);
  }

  @override
  Future<void> setAutoSync(String databasePath, bool enabled) {
    return _databaseSyncOrchestrator.setAutoSync(databasePath, enabled);
  }

  @override
  Future<SyncNowResult> syncNow(
    String databasePath, {
    SyncConflictResolution? resolution,
  }) {
    return _databaseSyncOrchestrator.syncNow(
      databasePath,
      resolution: resolution,
    );
  }
}
