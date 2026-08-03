import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loggy/loggy.dart';

import '../../../domain/models/database_dedup_result.dart';
import '../../coordinators/database_session_coordinator.dart';
import 'database_selection_event.dart';
import 'database_selection_state.dart';

class DatabaseSelectionBloc
    extends Bloc<DatabaseSelectionEvent, DatabaseSelectionState> {
  DatabaseSelectionBloc({required this.databaseSessionCoordinator})
    : super(const DatabaseSelectionInitial()) {
    on<CheckInitialDatabase>(_onCheckInitialDatabase);
    on<SelectExistingDatabase>(_onSelectExistingDatabase);
    on<OpenRecentDatabase>(_onOpenRecentDatabase);
    on<CreateNewDatabase>(_onCreateNewDatabase);
    on<SelectDriveDatabase>(_onSelectDriveDatabase);
    on<RemoveRecentDatabase>(_onRemoveRecentDatabase);
    on<ResolveDuplicateDecision>(_onResolveDuplicateDecision);
  }

  final DatabaseSessionCoordinatorContract databaseSessionCoordinator;
  DatabaseDuplicatePrompt? _pendingDuplicatePrompt;

  Future<void> _onCheckInitialDatabase(
    CheckInitialDatabase event,
    Emitter<DatabaseSelectionState> emit,
  ) async {
    _safeEmit(emit, const DatabaseSelectionLoading());
    try {
      final result = await databaseSessionCoordinator.checkInitialDatabase();
      _pendingDuplicatePrompt = null;
      _emitResult(emit, result);
    } catch (e, st) {
      logError('Failed to check initial database selection state.', e, st);
      _safeEmit(emit, DatabaseSelectionError(e.toString()));
      _safeEmit(emit, const DatabaseSelectionUnselected());
    }
  }

  Future<void> _onSelectExistingDatabase(
    SelectExistingDatabase event,
    Emitter<DatabaseSelectionState> emit,
  ) async {
    _safeEmit(
      emit,
      DatabaseSelectionLoading(recentDatabasePaths: state.recentDatabasePaths),
    );
    try {
      final result = await databaseSessionCoordinator.selectExistingDatabase(
        fileName: event.fileName,
        selectedPath: event.selectedPath,
        selectedBytes: event.selectedBytes,
        overwriteExisting: event.overwriteExisting,
      );
      _pendingDuplicatePrompt = null;
      _emitResult(emit, result);
    } catch (e, st) {
      logError('Failed while selecting an existing database file.', e, st);
      _safeEmit(
        emit,
        DatabaseSelectionError(
          e.toString(),
          recentDatabasePaths: state.recentDatabasePaths,
        ),
      );
      _safeEmit(
        emit,
        DatabaseSelectionUnselected(
          recentDatabasePaths: state.recentDatabasePaths,
        ),
      );
    }
  }

  Future<void> _onOpenRecentDatabase(
    OpenRecentDatabase event,
    Emitter<DatabaseSelectionState> emit,
  ) async {
    _safeEmit(
      emit,
      DatabaseSelectionLoading(recentDatabasePaths: state.recentDatabasePaths),
    );
    try {
      final result = await databaseSessionCoordinator.openRecentDatabase(
        event.path,
      );
      _pendingDuplicatePrompt = null;
      _emitResult(emit, result);
    } catch (e, st) {
      logError('Failed while opening recent database file.', e, st);
      _safeEmit(
        emit,
        DatabaseSelectionError(
          e.toString(),
          recentDatabasePaths: state.recentDatabasePaths,
        ),
      );
      _safeEmit(
        emit,
        DatabaseSelectionUnselected(
          recentDatabasePaths: state.recentDatabasePaths,
        ),
      );
    }
  }

  Future<void> _onCreateNewDatabase(
    CreateNewDatabase event,
    Emitter<DatabaseSelectionState> emit,
  ) async {
    _safeEmit(
      emit,
      DatabaseSelectionLoading(recentDatabasePaths: state.recentDatabasePaths),
    );
    try {
      final result = await databaseSessionCoordinator.createNewDatabase(
        databaseFileName: event.databaseFileName,
        password: event.password,
        keyFilePath: event.keyFilePath,
        biometricProtectionEnabled: event.biometricProtectionEnabled,
        generateKeyFile: event.generateKeyFile,
        generatedKeyFilePath: event.generatedKeyFilePath,
      );
      _pendingDuplicatePrompt = null;
      _emitResult(emit, result);
    } catch (e, st) {
      logError('Failed while creating a new database file.', e, st);
      _safeEmit(
        emit,
        DatabaseSelectionError(
          e.toString(),
          recentDatabasePaths: state.recentDatabasePaths,
        ),
      );
      _safeEmit(
        emit,
        DatabaseSelectionUnselected(
          recentDatabasePaths: state.recentDatabasePaths,
        ),
      );
    }
  }

  Future<void> _onSelectDriveDatabase(
    SelectDriveDatabase event,
    Emitter<DatabaseSelectionState> emit,
  ) async {
    _safeEmit(
      emit,
      DatabaseSelectionLoading(recentDatabasePaths: state.recentDatabasePaths),
    );
    try {
      final result = await databaseSessionCoordinator.selectDriveDatabase(
        remoteFileId: event.remoteFileId,
        remoteFileName: event.remoteFileName,
        overwriteExisting: event.overwriteExisting,
      );
      _pendingDuplicatePrompt = null;
      _emitResult(emit, result);
    } catch (e, st) {
      logError('Failed while selecting database from Drive.', e, st);
      _safeEmit(
        emit,
        DatabaseSelectionError(
          e.toString(),
          recentDatabasePaths: state.recentDatabasePaths,
        ),
      );
      _safeEmit(
        emit,
        DatabaseSelectionUnselected(
          recentDatabasePaths: state.recentDatabasePaths,
        ),
      );
    }
  }

  Future<void> _onRemoveRecentDatabase(
    RemoveRecentDatabase event,
    Emitter<DatabaseSelectionState> emit,
  ) async {
    _safeEmit(
      emit,
      DatabaseSelectionLoading(recentDatabasePaths: state.recentDatabasePaths),
    );
    try {
      final result = await databaseSessionCoordinator.removeRecentDatabase(
        path: event.path,
        mode: event.mode,
      );
      _emitResult(emit, result);
      _pendingDuplicatePrompt = null;
      _safeEmit(
        emit,
        DatabaseSelectionUnselected(
          recentDatabasePaths: result.recentDatabasePaths,
        ),
      );
    } catch (e, st) {
      logError('Failed while removing recent database.', e, st);
      _safeEmit(
        emit,
        DatabaseSelectionError(
          e.toString(),
          recentDatabasePaths: state.recentDatabasePaths,
        ),
      );
      _safeEmit(
        emit,
        DatabaseSelectionUnselected(
          recentDatabasePaths: state.recentDatabasePaths,
        ),
      );
    }
  }

  Future<void> _onResolveDuplicateDecision(
    ResolveDuplicateDecision event,
    Emitter<DatabaseSelectionState> emit,
  ) async {
    final pending = _pendingDuplicatePrompt;
    if (pending == null) {
      _safeEmit(
        emit,
        DatabaseSelectionError(
          'No pending duplicate operation found.',
          recentDatabasePaths: state.recentDatabasePaths,
        ),
      );
      return;
    }

    _safeEmit(
      emit,
      DatabaseSelectionLoading(recentDatabasePaths: state.recentDatabasePaths),
    );
    try {
      final result = await databaseSessionCoordinator.resolveDuplicateDecision(
        duplicatePrompt: pending,
        decision: event.decision,
      );
      if (event.decision == DatabaseDuplicateResolution.cancel) {
        _pendingDuplicatePrompt = null;
      }
      _emitResult(emit, result);
    } catch (e, st) {
      logError('Failed while resolving duplicate decision.', e, st);
      _safeEmit(
        emit,
        DatabaseSelectionError(
          e.toString(),
          recentDatabasePaths: state.recentDatabasePaths,
        ),
      );
      _safeEmit(
        emit,
        DatabaseSelectionUnselected(
          recentDatabasePaths: state.recentDatabasePaths,
        ),
      );
    }
  }

  void _emitResult(
    Emitter<DatabaseSelectionState> emit,
    DatabaseSelectionSessionResult result,
  ) {
    switch (result.status) {
      case DatabaseSessionStatus.success:
        if (result.path == null || result.path!.trim().isEmpty) {
          _safeEmit(
            emit,
            DatabaseSelectionError(
              'Invalid database path received from session coordinator.',
              recentDatabasePaths: result.recentDatabasePaths,
            ),
          );
          _safeEmit(
            emit,
            DatabaseSelectionUnselected(
              recentDatabasePaths: result.recentDatabasePaths,
            ),
          );
          return;
        }
        if (result.message != null && result.message!.trim().isNotEmpty) {
          _safeEmit(
            emit,
            DatabaseSelectionInfo(
              result.message!,
              recentDatabasePaths: result.recentDatabasePaths,
            ),
          );
        }
        _safeEmit(
          emit,
          DatabaseSelectionSuccess(
            result.path!,
            userMessage: result.message,
            promptBiometricSetup: result.promptBiometricSetup,
            recentDatabasePaths: result.recentDatabasePaths,
          ),
        );
        _pendingDuplicatePrompt = null;
      case DatabaseSessionStatus.error:
        _safeEmit(
          emit,
          DatabaseSelectionError(
            result.message ?? 'Unknown database selection error.',
            recentDatabasePaths: result.recentDatabasePaths,
          ),
        );
        _safeEmit(
          emit,
          DatabaseSelectionUnselected(
            recentDatabasePaths: result.recentDatabasePaths,
          ),
        );
      case DatabaseSessionStatus.info:
        _safeEmit(
          emit,
          DatabaseSelectionInfo(
            result.message ?? '',
            recentDatabasePaths: result.recentDatabasePaths,
          ),
        );
      case DatabaseSessionStatus.unselected:
        _safeEmit(
          emit,
          DatabaseSelectionUnselected(
            recentDatabasePaths: result.recentDatabasePaths,
          ),
        );
      case DatabaseSessionStatus.duplicateDecisionRequired:
        final duplicatePrompt = result.duplicatePrompt;
        if (duplicatePrompt == null) {
          _safeEmit(
            emit,
            DatabaseSelectionError(
              'Duplicate decision required but no prompt data was provided.',
              recentDatabasePaths: result.recentDatabasePaths,
            ),
          );
          return;
        }
        _pendingDuplicatePrompt = duplicatePrompt;
        _safeEmit(
          emit,
          DatabaseSelectionDuplicateDecisionRequired(
            duplicatePrompt: duplicatePrompt,
            message:
                result.message ??
                'Duplicate database detected. Choose how to continue.',
            recentDatabasePaths: result.recentDatabasePaths,
          ),
        );
    }
  }

  void _safeEmit(
    Emitter<DatabaseSelectionState> emit,
    DatabaseSelectionState nextState,
  ) {
    if (isClosed || emit.isDone) {
      return;
    }
    emit(nextState);
  }
}
