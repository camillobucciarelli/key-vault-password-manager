import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../domain/models/database_sync_mapping.dart';
import '../../domain/models/drive_remote_file.dart';
import '../../domain/models/sync_conflict.dart';
import '../../domain/repositories/database_sync_repository.dart';
import '../datasources/sync_metadata_data_source.dart';
import 'google_drive_api_service.dart';

class DatabaseSyncOrchestrator {
  DatabaseSyncOrchestrator({
    required SyncMetadataDataSource syncMetadataDataSource,
    required GoogleDriveApiService googleDriveApiService,
  }) : _syncMetadataDataSource = syncMetadataDataSource,
       _googleDriveApiService = googleDriveApiService;

  final SyncMetadataDataSource _syncMetadataDataSource;
  final GoogleDriveApiService _googleDriveApiService;

  Future<DatabaseSyncMapping> linkDatabaseToDrive({
    required String databasePath,
    String? remoteFileId,
    String? remoteFileName,
  }) async {
    final dbFile = File(databasePath);
    if (!await dbFile.exists()) {
      throw Exception('Database file not found.');
    }

    final bytes = await dbFile.readAsBytes();

    late final DriveRemoteFile remote;
    late final DatabaseSyncMapping mapping;
    if (remoteFileId != null && remoteFileId.trim().isNotEmpty) {
      remote = await _googleDriveApiService.getFileMetadata(remoteFileId);
      mapping = DatabaseSyncMapping(
        databasePath: databasePath,
        driveFileId: remote.id,
        driveFileName: remote.name,
        lastSyncedLocalChecksum: null,
        lastSyncedRemoteChecksum: null,
        lastSyncedRemoteModifiedTime: remote.modifiedTime,
        lastSyncAt: null,
        autoSyncEnabled: true,
      );
    } else {
      final desiredName = _normalizeFileName(
        remoteFileName,
        fallbackPath: databasePath,
      );
      remote = await _googleDriveApiService.createFile(
        fileName: desiredName,
        bytes: bytes,
      );

      final checksum = md5.convert(bytes).toString();
      mapping = DatabaseSyncMapping(
        databasePath: databasePath,
        driveFileId: remote.id,
        driveFileName: remote.name,
        lastSyncedLocalChecksum: checksum,
        lastSyncedRemoteChecksum: remote.md5Checksum ?? checksum,
        lastSyncedRemoteModifiedTime: remote.modifiedTime,
        lastSyncAt: DateTime.now(),
        autoSyncEnabled: true,
      );
    }

    await _syncMetadataDataSource.upsertMapping(mapping);
    return mapping;
  }

  Future<SyncNowResult> syncNow(
    String databasePath, {
    SyncConflictResolution? resolution,
  }) async {
    final mapping = await _syncMetadataDataSource.getMapping(databasePath);
    if (mapping == null) {
      throw Exception('Current database is not linked to Google Drive.');
    }

    final dbFile = File(databasePath);
    if (!await dbFile.exists()) {
      throw Exception('Database file not found.');
    }

    final localBytes = await dbFile.readAsBytes();
    final localChecksum = md5.convert(localBytes).toString();
    final remote = await _googleDriveApiService.getFileMetadata(
      mapping.driveFileId,
    );
    final remoteChecksum = remote.md5Checksum ?? '';

    final previousLocal = mapping.lastSyncedLocalChecksum;
    final previousRemote = mapping.lastSyncedRemoteChecksum;

    final localChanged =
        previousLocal == null || previousLocal != localChecksum;
    final remoteChanged =
        previousRemote == null || previousRemote != remoteChecksum;

    if (localChanged && remoteChanged) {
      if (resolution == null || resolution == SyncConflictResolution.cancel) {
        return SyncNowConflict(
          SyncConflict(
            databasePath: databasePath,
            driveFileId: mapping.driveFileId,
            driveFileName: mapping.driveFileName,
            localChecksum: localChecksum,
            remoteChecksum: remoteChecksum,
            remoteModifiedTime: remote.modifiedTime,
          ),
        );
      }

      if (resolution == SyncConflictResolution.keepLocal) {
        final updated = await _googleDriveApiService.updateFile(
          fileId: mapping.driveFileId,
          bytes: localBytes,
        );
        await _syncMetadataDataSource.upsertMapping(
          mapping.copyWith(
            lastSyncedLocalChecksum: localChecksum,
            lastSyncedRemoteChecksum: updated.md5Checksum ?? localChecksum,
            lastSyncedRemoteModifiedTime: updated.modifiedTime,
            lastSyncAt: DateTime.now(),
            clearError: true,
          ),
        );
        return const SyncNowSuccess();
      }

      await _backupFile(databasePath);
      final downloaded = await _googleDriveApiService.downloadFile(
        mapping.driveFileId,
      );
      await dbFile.writeAsBytes(downloaded, flush: true);
      final refreshedLocal = md5.convert(downloaded).toString();

      await _syncMetadataDataSource.upsertMapping(
        mapping.copyWith(
          lastSyncedLocalChecksum: refreshedLocal,
          lastSyncedRemoteChecksum: remoteChecksum.isEmpty
              ? refreshedLocal
              : remoteChecksum,
          lastSyncedRemoteModifiedTime: remote.modifiedTime,
          lastSyncAt: DateTime.now(),
          clearError: true,
        ),
      );
      return const SyncNowSuccess();
    }

    if (localChanged) {
      final updated = await _googleDriveApiService.updateFile(
        fileId: mapping.driveFileId,
        bytes: localBytes,
      );
      await _syncMetadataDataSource.upsertMapping(
        mapping.copyWith(
          lastSyncedLocalChecksum: localChecksum,
          lastSyncedRemoteChecksum: updated.md5Checksum ?? localChecksum,
          lastSyncedRemoteModifiedTime: updated.modifiedTime,
          lastSyncAt: DateTime.now(),
          clearError: true,
        ),
      );
      return const SyncNowSuccess();
    }

    if (remoteChanged) {
      await _backupFile(databasePath);
      final downloaded = await _googleDriveApiService.downloadFile(
        mapping.driveFileId,
      );
      await dbFile.writeAsBytes(downloaded, flush: true);
      final refreshedLocal = md5.convert(downloaded).toString();

      await _syncMetadataDataSource.upsertMapping(
        mapping.copyWith(
          lastSyncedLocalChecksum: refreshedLocal,
          lastSyncedRemoteChecksum: remoteChecksum.isEmpty
              ? refreshedLocal
              : remoteChecksum,
          lastSyncedRemoteModifiedTime: remote.modifiedTime,
          lastSyncAt: DateTime.now(),
          clearError: true,
        ),
      );
      return const SyncNowSuccess();
    }

    await _syncMetadataDataSource.upsertMapping(
      mapping.copyWith(lastSyncAt: DateTime.now(), clearError: true),
    );
    return const SyncNowSuccess();
  }

  Future<List<DriveRemoteFile>> listRemoteFiles({String? query}) {
    return _googleDriveApiService.listKdbxFilesInDrive(query: query);
  }

  Future<Uint8List> downloadRemoteFile(String fileId) {
    return _googleDriveApiService.downloadFile(fileId);
  }

  Future<void> setAutoSync(String databasePath, bool enabled) async {
    final mapping = await _syncMetadataDataSource.getMapping(databasePath);
    if (mapping == null) {
      throw Exception('Current database is not linked to Google Drive.');
    }
    await _syncMetadataDataSource.upsertMapping(
      mapping.copyWith(autoSyncEnabled: enabled),
    );
  }

  Future<DatabaseSyncMapping?> getMapping(String databasePath) {
    return _syncMetadataDataSource.getMapping(databasePath);
  }

  String _normalizeFileName(String? custom, {required String fallbackPath}) {
    final candidate = (custom == null || custom.trim().isEmpty)
        ? fallbackPath.split(Platform.pathSeparator).last
        : custom.trim();
    return candidate.toLowerCase().endsWith('.kdbx')
        ? candidate
        : '$candidate.kdbx';
  }

  Future<void> _backupFile(String databasePath) async {
    final source = File(databasePath);
    if (!await source.exists()) {
      return;
    }

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final backupPath = '$databasePath.$timestamp.bak';
    await source.copy(backupPath);
  }
}
