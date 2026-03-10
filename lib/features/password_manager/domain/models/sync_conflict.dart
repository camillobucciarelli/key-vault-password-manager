import 'package:equatable/equatable.dart';

enum SyncConflictResolution { keepLocal, useRemote, cancel }

class SyncConflict extends Equatable {
  const SyncConflict({
    required this.databasePath,
    required this.driveFileId,
    required this.driveFileName,
    required this.localChecksum,
    required this.remoteChecksum,
    this.remoteModifiedTime,
    this.previousLocalChecksum,
    this.previousRemoteChecksum,
    this.localChanged,
    this.remoteChanged,
    this.firstSyncWithoutBaseline,
    this.remoteChecksumComputedFromDownload,
  });

  final String databasePath;
  final String driveFileId;
  final String driveFileName;
  final String localChecksum;
  final String remoteChecksum;
  final DateTime? remoteModifiedTime;
  final String? previousLocalChecksum;
  final String? previousRemoteChecksum;
  final bool? localChanged;
  final bool? remoteChanged;
  final bool? firstSyncWithoutBaseline;
  final bool? remoteChecksumComputedFromDownload;

  @override
  List<Object?> get props => [
    databasePath,
    driveFileId,
    driveFileName,
    localChecksum,
    remoteChecksum,
    remoteModifiedTime,
    previousLocalChecksum,
    previousRemoteChecksum,
    localChanged,
    remoteChanged,
    firstSyncWithoutBaseline,
    remoteChecksumComputedFromDownload,
  ];
}
