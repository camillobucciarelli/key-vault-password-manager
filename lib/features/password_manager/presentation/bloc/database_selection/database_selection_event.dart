import 'package:equatable/equatable.dart';
import 'package:password_manager/core/utils/redacted_value.dart';

import '../../../domain/models/database_dedup_result.dart';

abstract class DatabaseSelectionEvent extends Equatable {
  const DatabaseSelectionEvent();

  @override
  List<Object> get props => [];
}

class CheckInitialDatabase extends DatabaseSelectionEvent {}

class SelectExistingDatabase extends DatabaseSelectionEvent {
  const SelectExistingDatabase({
    required this.fileName,
    this.selectedPath,
    this.selectedBytes,
    this.overwriteExisting = false,
  });

  final String fileName;
  final String? selectedPath;
  final List<int>? selectedBytes;
  final bool overwriteExisting;

  @override
  List<Object> get props => [
    fileName,
    selectedPath ?? '',
    selectedBytes?.length ?? -1,
    overwriteExisting,
  ];
}

class OpenRecentDatabase extends DatabaseSelectionEvent {
  const OpenRecentDatabase(this.path);

  final String path;

  @override
  List<Object> get props => [path];
}

class CreateNewDatabase extends DatabaseSelectionEvent {
  final String databaseFileName;
  final String password;
  final String? keyFilePath;
  final bool biometricProtectionEnabled;
  final bool generateKeyFile;
  final String? generatedKeyFilePath;

  const CreateNewDatabase({
    required this.databaseFileName,
    required this.password,
    this.keyFilePath,
    this.biometricProtectionEnabled = false,
    this.generateKeyFile = false,
    this.generatedKeyFilePath,
  });

  @override
  List<Object> get props => [
    databaseFileName,
    RedactedValue<String>(password),
    RedactedValue<String>(
      keyFilePath ?? '',
      redaction: '<redacted keyFilePath>',
    ),
    biometricProtectionEnabled,
    generateKeyFile,
    RedactedValue<String>(
      generatedKeyFilePath ?? '',
      redaction: '<redacted generatedKeyFilePath>',
    ),
  ];
}

class SelectDriveDatabase extends DatabaseSelectionEvent {
  const SelectDriveDatabase({
    required this.remoteFileId,
    required this.remoteFileName,
    required this.overwriteExisting,
  });

  final String remoteFileId;
  final String remoteFileName;
  final bool overwriteExisting;

  @override
  List<Object> get props => [
    RedactedValue<String>(remoteFileId, redaction: '<redacted remoteFileId>'),
    remoteFileName,
    overwriteExisting,
  ];
}

enum RecentDatabaseRemovalMode { removeOnly, removeAndDeleteFile }

class RemoveRecentDatabase extends DatabaseSelectionEvent {
  const RemoveRecentDatabase({required this.path, required this.mode});

  final String path;
  final RecentDatabaseRemovalMode mode;

  @override
  List<Object> get props => [path, mode];
}

class ResolveDuplicateDecision extends DatabaseSelectionEvent {
  const ResolveDuplicateDecision(this.decision);

  final DatabaseDuplicateResolution decision;

  @override
  List<Object> get props => [decision];
}
