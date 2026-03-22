import 'package:equatable/equatable.dart';

import '../../coordinators/database_session_coordinator.dart';

abstract class DatabaseSelectionState extends Equatable {
  const DatabaseSelectionState({this.recentDatabasePaths = const []});

  final List<String> recentDatabasePaths;

  @override
  List<Object?> get props => [recentDatabasePaths];
}

class DatabaseSelectionInitial extends DatabaseSelectionState {
  const DatabaseSelectionInitial({super.recentDatabasePaths});
}

class DatabaseSelectionLoading extends DatabaseSelectionState {
  const DatabaseSelectionLoading({super.recentDatabasePaths});
}

class DatabaseSelectionUnselected extends DatabaseSelectionState {
  const DatabaseSelectionUnselected({super.recentDatabasePaths});
}

class DatabaseSelectionSuccess extends DatabaseSelectionState {
  final String path;
  final String? userMessage;
  final bool promptBiometricSetup;

  const DatabaseSelectionSuccess(
    this.path, {
    this.userMessage,
    this.promptBiometricSetup = false,
    super.recentDatabasePaths,
  });

  @override
  List<Object?> get props => [
    path,
    userMessage,
    promptBiometricSetup,
    recentDatabasePaths,
  ];
}

class DatabaseSelectionError extends DatabaseSelectionState {
  final String message;

  const DatabaseSelectionError(this.message, {super.recentDatabasePaths});

  @override
  List<Object?> get props => [message, recentDatabasePaths];
}

class DatabaseSelectionInfo extends DatabaseSelectionState {
  final String message;

  const DatabaseSelectionInfo(this.message, {super.recentDatabasePaths});

  @override
  List<Object?> get props => [message, recentDatabasePaths];
}

class DatabaseSelectionDuplicateDecisionRequired
    extends DatabaseSelectionState {
  const DatabaseSelectionDuplicateDecisionRequired({
    required this.duplicatePrompt,
    required this.message,
    super.recentDatabasePaths,
  });

  final DatabaseDuplicatePrompt duplicatePrompt;
  final String message;

  @override
  List<Object?> get props => [duplicatePrompt, message, recentDatabasePaths];
}
