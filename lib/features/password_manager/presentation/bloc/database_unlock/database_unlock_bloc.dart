import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loggy/loggy.dart';

import '../../../data/datasources/biometric_data_source.dart';
import '../../../domain/errors/database_access_failure.dart';
import '../../coordinators/database_session_coordinator.dart';
import '../database_selection/database_selection_bloc.dart' show failureMessage;
import 'database_unlock_event.dart';
import 'database_unlock_state.dart';

class DatabaseUnlockBloc
    extends Bloc<DatabaseUnlockEvent, DatabaseUnlockState> {
  DatabaseUnlockBloc({
    required String databasePath,
    required this.biometricDataSource,
    required this.databaseSessionCoordinator,
  }) : super(DatabaseUnlockState.initial(databasePath: databasePath)) {
    on<InitializeDatabaseUnlock>(_onInitializeDatabaseUnlock);
    on<RetryBiometricAuthentication>(_onRetryBiometricAuthentication);
    on<RequestManualUnlockFallback>(_onRequestManualUnlockFallback);
    on<UnlockWithManualCredentials>(_onUnlockWithManualCredentials);
    on<UpdateKeyFilePath>(_onUpdateKeyFilePath);
  }

  final BiometricDataSource biometricDataSource;
  final DatabaseSessionCoordinator databaseSessionCoordinator;

  Future<void> _onInitializeDatabaseUnlock(
    InitializeDatabaseUnlock event,
    Emitter<DatabaseUnlockState> emit,
  ) async {
    _safeEmit(
      emit,
      state.copyWith(phase: UnlockPhase.initializing, clearError: true),
    );
    try {
      final biometricAvailable = await biometricDataSource
          .isBiometricAvailable();
      final bootstrap = await databaseSessionCoordinator.initializeUnlock(
        databasePath: state.databasePath,
        biometricAvailable: biometricAvailable,
      );

      var nextState = state.copyWith(
        keyFilePath: bootstrap.keyFilePath,
        clearKeyFilePath: bootstrap.keyFilePath == null,
        biometricAvailable: bootstrap.biometricAvailable,
        clearError: true,
      );

      if (bootstrap.biometricRequired && bootstrap.biometricAvailable) {
        nextState = nextState.copyWith(phase: UnlockPhase.biometricGate);
        _safeEmit(emit, nextState);

        final biometricsOk = await biometricDataSource.authenticate(
          reason: 'Authenticate to unlock your password database',
        );

        nextState = nextState.copyWith(
          biometricPrompted: true,
          biometricVerified: biometricsOk,
          clearError: true,
        );

        if (biometricsOk) {
          _safeEmit(emit, nextState.copyWith(phase: UnlockPhase.ready));
          await _tryStoredCredentialsUnlock(emit);
        } else {
          _safeEmit(
            emit,
            nextState.copyWith(
              phase: UnlockPhase.biometricGate,
              errorMessage:
                  'Biometric authentication failed. Retry or unlock manually.',
            ),
          );
        }
        return;
      }

      _safeEmit(
        emit,
        nextState.copyWith(
          phase: UnlockPhase.ready,
          biometricPrompted: bootstrap.biometricRequired,
          biometricVerified:
              !bootstrap.biometricRequired || !bootstrap.biometricAvailable,
          errorMessage:
              bootstrap.biometricRequired && !bootstrap.biometricAvailable
              ? 'Biometric authentication is not available on this device.'
              : null,
        ),
      );
    } catch (e, st) {
      logError('Failed to initialize database unlock state.', e, st);
      _emitTypedOrGenericFailure(emit, e, genericPhase: UnlockPhase.failure);
    }
  }

  Future<void> _onRetryBiometricAuthentication(
    RetryBiometricAuthentication event,
    Emitter<DatabaseUnlockState> emit,
  ) async {
    if (state.isDecrypting) {
      return;
    }
    _safeEmit(
      emit,
      state.copyWith(phase: UnlockPhase.biometricGate, clearError: true),
    );
    final isOk = await biometricDataSource.authenticate(
      reason: 'Authenticate to unlock your password database',
    );

    _safeEmit(
      emit,
      state.copyWith(
        phase: isOk ? UnlockPhase.ready : UnlockPhase.biometricGate,
        biometricPrompted: true,
        biometricVerified: isOk,
        errorMessage: isOk ? null : 'Biometric authentication failed.',
      ),
    );

    if (isOk) {
      await _tryStoredCredentialsUnlock(emit);
    }
  }

  /// Escapes the biometric gate to the manual credential form. Session-only:
  /// nothing is persisted, so biometrics gate the next launch again. The
  /// master password is the primary credential (it derives the KDBX key) —
  /// this is a convenience opt-out, not a security bypass.
  void _onRequestManualUnlockFallback(
    RequestManualUnlockFallback event,
    Emitter<DatabaseUnlockState> emit,
  ) {
    if (state.isDecrypting) {
      return;
    }
    _safeEmit(
      emit,
      state.copyWith(
        phase: UnlockPhase.ready,
        manualFallbackRequested: true,
        clearError: true,
      ),
    );
  }

  Future<void> _onUnlockWithManualCredentials(
    UnlockWithManualCredentials event,
    Emitter<DatabaseUnlockState> emit,
  ) async {
    // C-4: decrypting blocks duplicate submit/back/credential edits.
    if (state.isDecrypting) {
      return;
    }
    if (_requiresBiometricGate()) {
      _safeEmit(
        emit,
        state.copyWith(
          errorMessage:
              'Use biometric authentication before unlocking the database.',
        ),
      );
      return;
    }

    // Enter `decrypting` immediately, before awaiting the KDBX read.
    _safeEmit(
      emit,
      state.copyWith(
        phase: UnlockPhase.decrypting,
        clearError: true,
        clearProgress: true,
      ),
    );

    try {
      await databaseSessionCoordinator.unlockWithManualCredentials(
        databasePath: state.databasePath,
        password: event.password,
        keyFilePath: event.keyFilePath,
      );

      _safeEmit(
        emit,
        state.copyWith(
          phase: UnlockPhase.unlocked,
          keyFilePath: event.keyFilePath,
          clearError: true,
        ),
      );
    } catch (e, st) {
      logError('Manual database unlock failed.', e, st);
      _emitTypedOrGenericFailure(
        emit,
        e,
        genericPhase: UnlockPhase.ready,
        fallback: 'Unable to unlock database with provided credentials.',
      );
    }
  }

  Future<void> _onUpdateKeyFilePath(
    UpdateKeyFilePath event,
    Emitter<DatabaseUnlockState> emit,
  ) async {
    if (state.isDecrypting) {
      return;
    }
    final normalizedKeyFilePath = event.keyFilePath?.trim();
    final nextKeyFilePath =
        (normalizedKeyFilePath == null || normalizedKeyFilePath.isEmpty)
        ? null
        : normalizedKeyFilePath;
    try {
      await databaseSessionCoordinator.updateKeyFilePath(
        databasePath: state.databasePath,
        keyFilePath: nextKeyFilePath,
      );
    } on DatabaseAccessFailure catch (failure) {
      _safeEmit(
        emit,
        state.copyWith(failure: failure, errorMessage: failureMessage(failure)),
      );
      return;
    }
    _safeEmit(
      emit,
      state.copyWith(
        keyFilePath: nextKeyFilePath,
        clearKeyFilePath: nextKeyFilePath == null,
        clearError: true,
      ),
    );
  }

  Future<void> _tryStoredCredentialsUnlock(
    Emitter<DatabaseUnlockState> emit,
  ) async {
    _safeEmit(
      emit,
      state.copyWith(
        phase: UnlockPhase.decrypting,
        clearError: true,
        clearProgress: true,
      ),
    );

    final hasStoredPassword = await databaseSessionCoordinator
        .hasStoredMasterPassword();
    final hasKeyFile =
        state.keyFilePath != null && state.keyFilePath!.isNotEmpty;

    if (!hasStoredPassword && !hasKeyFile) {
      _safeEmit(
        emit,
        state.copyWith(
          phase: UnlockPhase.ready,
          errorMessage:
              'No saved credentials found. Insert password or select a key file.',
        ),
      );
      return;
    }

    try {
      await databaseSessionCoordinator.unlockWithStoredCredentials(
        databasePath: state.databasePath,
        keyFilePath: state.keyFilePath,
      );
      _safeEmit(
        emit,
        state.copyWith(phase: UnlockPhase.unlocked, clearError: true),
      );
    } catch (e, st) {
      logError(
        'Stored credentials unlock failed after biometric success.',
        e,
        st,
      );
      _emitTypedOrGenericFailure(
        emit,
        e,
        genericPhase: UnlockPhase.ready,
        fallback: 'Saved credentials are not valid. Unlock manually.',
      );
    }
  }

  bool _requiresBiometricGate() {
    return state.biometricAvailable &&
        !state.biometricVerified &&
        !state.manualFallbackRequested;
  }

  /// Wrong password / missing key file stay recoverable in-place (`ready`
  /// with an inline field error); a bad database file is a dead end until
  /// the user goes back (`failure`).
  UnlockPhase _phaseForFailure(DatabaseAccessFailure failure) =>
      switch (failure) {
        InvalidCredentialsFailure() => UnlockPhase.ready,
        KeyFileMissingFailure() => UnlockPhase.ready,
        DatabaseFileMissingFailure() => UnlockPhase.failure,
        InvalidDatabaseFileFailure() => UnlockPhase.failure,
        CorruptDatabaseFailure() => UnlockPhase.failure,
      };

  void _emitTypedOrGenericFailure(
    Emitter<DatabaseUnlockState> emit,
    Object error, {
    required UnlockPhase genericPhase,
    String? fallback,
  }) {
    if (error is DatabaseAccessFailure) {
      _safeEmit(
        emit,
        state.copyWith(
          phase: _phaseForFailure(error),
          failure: error,
          errorMessage: failureMessage(error),
        ),
      );
      return;
    }
    _safeEmit(
      emit,
      state.copyWith(
        phase: genericPhase,
        clearError: true,
        errorMessage: fallback ?? 'Unable to complete the requested operation.',
      ),
    );
  }

  void _safeEmit(
    Emitter<DatabaseUnlockState> emit,
    DatabaseUnlockState nextState,
  ) {
    if (isClosed || emit.isDone) {
      return;
    }
    emit(nextState);
  }
}
