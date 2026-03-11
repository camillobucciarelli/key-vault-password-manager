import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:loggy/loggy.dart';

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
    final remoteChecksumSnapshot = await _resolveRemoteChecksum(
      remoteFileId: mapping.driveFileId,
      metadataChecksum: remote.md5Checksum,
    );
    final remoteChecksum = remoteChecksumSnapshot.value;

    final previousLocal = mapping.lastSyncedLocalChecksum;
    final previousRemote = mapping.lastSyncedRemoteChecksum;

    final firstSyncWithoutBaseline =
        previousLocal == null && previousRemote == null;

    if (firstSyncWithoutBaseline) {
      final checksumsMatch = localChecksum == remoteChecksum;
      if (checksumsMatch) {
        await _syncMetadataDataSource.upsertMapping(
          mapping.copyWith(
            lastSyncedLocalChecksum: localChecksum,
            lastSyncedRemoteChecksum: remoteChecksum,
            lastSyncedRemoteModifiedTime: remote.modifiedTime,
            lastSyncAt: DateTime.now(),
            clearError: true,
          ),
        );
        return const SyncNowSuccess();
      }

      _logSyncConflict(
        databasePath: databasePath,
        driveFileName: mapping.driveFileName,
        localChecksum: localChecksum,
        remoteChecksum: remoteChecksum,
        previousLocalChecksum: previousLocal,
        previousRemoteChecksum: previousRemote,
        localChanged: true,
        remoteChanged: true,
        firstSyncWithoutBaseline: true,
        remoteChecksumComputedFromDownload:
            remoteChecksumSnapshot.computedFromDownload,
      );

      if (resolution == null || resolution == SyncConflictResolution.cancel) {
        return SyncNowConflict(
          SyncConflict(
            databasePath: databasePath,
            driveFileId: mapping.driveFileId,
            driveFileName: mapping.driveFileName,
            localChecksum: localChecksum,
            remoteChecksum: remoteChecksum,
            remoteModifiedTime: remote.modifiedTime,
            previousLocalChecksum: previousLocal,
            previousRemoteChecksum: previousRemote,
            localChanged: true,
            remoteChanged: true,
            firstSyncWithoutBaseline: true,
            remoteChecksumComputedFromDownload:
                remoteChecksumSnapshot.computedFromDownload,
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
          lastSyncedRemoteChecksum: remoteChecksum,
          lastSyncedRemoteModifiedTime: remote.modifiedTime,
          lastSyncAt: DateTime.now(),
          clearError: true,
        ),
      );
      return const SyncNowSuccess();
    }

    final localChanged =
        previousLocal == null || previousLocal != localChecksum;
    final remoteChanged =
        previousRemote == null || previousRemote != remoteChecksum;

    if (localChanged && remoteChanged) {
      _logSyncConflict(
        databasePath: databasePath,
        driveFileName: mapping.driveFileName,
        localChecksum: localChecksum,
        remoteChecksum: remoteChecksum,
        previousLocalChecksum: previousLocal,
        previousRemoteChecksum: previousRemote,
        localChanged: localChanged,
        remoteChanged: remoteChanged,
        firstSyncWithoutBaseline: false,
        remoteChecksumComputedFromDownload:
            remoteChecksumSnapshot.computedFromDownload,
      );

      if (resolution == null || resolution == SyncConflictResolution.cancel) {
        return SyncNowConflict(
          SyncConflict(
            databasePath: databasePath,
            driveFileId: mapping.driveFileId,
            driveFileName: mapping.driveFileName,
            localChecksum: localChecksum,
            remoteChecksum: remoteChecksum,
            remoteModifiedTime: remote.modifiedTime,
            previousLocalChecksum: previousLocal,
            previousRemoteChecksum: previousRemote,
            localChanged: localChanged,
            remoteChanged: remoteChanged,
            firstSyncWithoutBaseline: false,
            remoteChecksumComputedFromDownload:
                remoteChecksumSnapshot.computedFromDownload,
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
          lastSyncedRemoteChecksum: remoteChecksum,
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
          lastSyncedRemoteChecksum: remoteChecksum,
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

  Future<void> removeMapping(String databasePath) {
    return _syncMetadataDataSource.removeMapping(databasePath);
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

  Future<_RemoteChecksumSnapshot> _resolveRemoteChecksum({
    required String remoteFileId,
    required String? metadataChecksum,
  }) async {
    final normalizedMetadataChecksum = metadataChecksum?.trim();
    if (normalizedMetadataChecksum != null &&
        normalizedMetadataChecksum.isNotEmpty) {
      return _RemoteChecksumSnapshot(
        value: normalizedMetadataChecksum,
        computedFromDownload: false,
      );
    }

    final downloaded = await _googleDriveApiService.downloadFile(remoteFileId);
    final checksum = md5.convert(downloaded).toString();
    return _RemoteChecksumSnapshot(value: checksum, computedFromDownload: true);
  }

  void _logSyncConflict({
    required String databasePath,
    required String driveFileName,
    required String localChecksum,
    required String remoteChecksum,
    required String? previousLocalChecksum,
    required String? previousRemoteChecksum,
    required bool localChanged,
    required bool remoteChanged,
    required bool firstSyncWithoutBaseline,
    required bool remoteChecksumComputedFromDownload,
  }) {
    logWarning(
      'Sync conflict details '
      '(db: $databasePath, file: $driveFileName, '
      'localChanged: $localChanged, remoteChanged: $remoteChanged, '
      'firstSyncWithoutBaseline: $firstSyncWithoutBaseline, '
      'remoteChecksumComputedFromDownload: '
      '$remoteChecksumComputedFromDownload, '
      'previousLocalChecksum: ${previousLocalChecksum ?? 'null'}, '
      'previousRemoteChecksum: ${previousRemoteChecksum ?? 'null'}, '
      'localChecksum: $localChecksum, remoteChecksum: $remoteChecksum)',
    );
  }
}

class _RemoteChecksumSnapshot {
  const _RemoteChecksumSnapshot({
    required this.value,
    required this.computedFromDownload,
  });

  final String value;
  final bool computedFromDownload;
}
