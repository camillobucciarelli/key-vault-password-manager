import 'package:equatable/equatable.dart';

enum SyncConflictResolution { keepLocal, useRemote, cancel }

class SyncConflict extends Equatable {
  const SyncConflict({
    required this.databasePath,
    required this.remoteFileId,
    required this.remoteFileName,
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
  final String remoteFileId;
  final String remoteFileName;
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
    remoteFileId,
    remoteFileName,
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
