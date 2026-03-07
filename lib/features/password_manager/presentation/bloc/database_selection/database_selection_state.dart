import 'package:equatable/equatable.dart';

abstract class DatabaseSelectionState extends Equatable {
  const DatabaseSelectionState();

  @override
  List<Object?> get props => [];
}

class DatabaseSelectionInitial extends DatabaseSelectionState {}

class DatabaseSelectionLoading extends DatabaseSelectionState {}

class DatabaseSelectionUnselected extends DatabaseSelectionState {}

class DatabaseSelectionSuccess extends DatabaseSelectionState {
  final String path;

  const DatabaseSelectionSuccess(this.path);

  @override
  List<Object?> get props => [path];
}

class DatabaseSelectionError extends DatabaseSelectionState {
  final String message;

  const DatabaseSelectionError(this.message);

  @override
  List<Object?> get props => [message];
}
