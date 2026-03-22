import 'package:equatable/equatable.dart';

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
    password,
    keyFilePath ?? '',
    biometricProtectionEnabled,
    generateKeyFile,
    generatedKeyFilePath ?? '',
  ];
}

class SelectDriveDatabaseLocalCopy extends DatabaseSelectionEvent {
  const SelectDriveDatabaseLocalCopy({
    required this.localPath,
    required this.remoteFileId,
  });

  final String localPath;
  final String remoteFileId;

  @override
  List<Object> get props => [localPath, remoteFileId];
}

enum RecentDatabaseRemovalMode { removeOnly, removeAndDeleteFile }

class RemoveRecentDatabase extends DatabaseSelectionEvent {
  const RemoveRecentDatabase({required this.path, required this.mode});

  final String path;
  final RecentDatabaseRemovalMode mode;

  @override
  List<Object> get props => [path, mode];
}
