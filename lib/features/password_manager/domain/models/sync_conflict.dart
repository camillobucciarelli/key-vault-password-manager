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
  });

  final String databasePath;
  final String driveFileId;
  final String driveFileName;
  final String localChecksum;
  final String remoteChecksum;
  final DateTime? remoteModifiedTime;

  @override
  List<Object?> get props => [
    databasePath,
    driveFileId,
    driveFileName,
    localChecksum,
    remoteChecksum,
    remoteModifiedTime,
  ];
}
