import 'package:equatable/equatable.dart';

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

  const DatabaseSelectionSuccess(
    this.path, {
    this.userMessage,
    super.recentDatabasePaths,
  });

  @override
  List<Object?> get props => [path, userMessage, recentDatabasePaths];
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
