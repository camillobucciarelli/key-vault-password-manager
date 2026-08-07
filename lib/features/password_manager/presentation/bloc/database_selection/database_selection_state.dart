import 'package:equatable/equatable.dart';

import '../../../domain/errors/database_access_failure.dart';
import '../../../domain/models/create_database_step.dart';
import '../../../domain/models/database_selection_item.dart';
import '../../coordinators/database_session_coordinator.dart';

abstract class DatabaseSelectionState extends Equatable {
  const DatabaseSelectionState({this.items = const []});

  /// C-1 selection metadata. Replaces the former
  /// `List<String> recentDatabasePaths`.
  final List<DatabaseSelectionItem> items;

  @override
  List<Object?> get props => [items];
}

class DatabaseSelectionInitial extends DatabaseSelectionState {
  const DatabaseSelectionInitial({super.items});
}

class DatabaseSelectionLoading extends DatabaseSelectionState {
  const DatabaseSelectionLoading({super.items});
}

class DatabaseSelectionUnselected extends DatabaseSelectionState {
  const DatabaseSelectionUnselected({super.items});
}

class DatabaseSelectionSuccess extends DatabaseSelectionState {
  final String path;
  final String? userMessage;
  final bool promptBiometricSetup;

  const DatabaseSelectionSuccess(
    this.path, {
    this.userMessage,
    this.promptBiometricSetup = false,
    super.items,
  });

  @override
  List<Object?> get props => [path, userMessage, promptBiometricSetup, items];
}

/// C-3 typed failure surfaced by the coordinator (missing database, invalid
/// selection, corrupt KDBX, missing key file, invalid credentials). `null`
/// [failure] with a non-empty [message] means a generic/unexpected error —
/// the message is still never a raw `e.toString()` or a full path.
class DatabaseSelectionError extends DatabaseSelectionState {
  final String message;
  final DatabaseAccessFailure? failure;

  const DatabaseSelectionError(this.message, {this.failure, super.items});

  @override
  List<Object?> get props => [message, failure, items];
}

class DatabaseSelectionInfo extends DatabaseSelectionState {
  final String message;

  const DatabaseSelectionInfo(this.message, {super.items});

  @override
  List<Object?> get props => [message, items];
}

class DatabaseSelectionDuplicateDecisionRequired
    extends DatabaseSelectionState {
  const DatabaseSelectionDuplicateDecisionRequired({
    required this.duplicatePrompt,
    required this.message,
    super.items,
  });

  final DatabaseDuplicatePrompt duplicatePrompt;
  final String message;

  @override
  List<Object?> get props => [duplicatePrompt, message, items];
}

/// C-5: non-secret create-database wizard position. The password itself
/// never appears here — see `CreateNewDatabase` event / `RedactedValue`.
class DatabaseSelectionCreateStep extends DatabaseSelectionState {
  const DatabaseSelectionCreateStep(this.step, {super.items});

  final CreateDatabaseStep step;

  @override
  List<Object?> get props => [step, items];
}
