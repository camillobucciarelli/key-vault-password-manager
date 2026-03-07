import 'package:equatable/equatable.dart';

abstract class DatabaseSelectionEvent extends Equatable {
  const DatabaseSelectionEvent();

  @override
  List<Object> get props => [];
}

class CheckInitialDatabase extends DatabaseSelectionEvent {}

class SelectExistingDatabase extends DatabaseSelectionEvent {}

class CreateNewDatabase extends DatabaseSelectionEvent {
  final String password;
  final String? keyFilePath;
  final bool generateKeyFile;
  final String? generatedKeyFilePath;

  const CreateNewDatabase({
    required this.password,
    this.keyFilePath,
    this.generateKeyFile = false,
    this.generatedKeyFilePath,
  });

  @override
  List<Object> get props => [
    password,
    keyFilePath ?? '',
    generateKeyFile,
    generatedKeyFilePath ?? '',
  ];
}
