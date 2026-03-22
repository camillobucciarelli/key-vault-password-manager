import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loggy/loggy.dart';

import '../../../data/datasources/biometric_data_source.dart';
import '../../coordinators/database_session_coordinator.dart';
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
    on<UnlockWithManualCredentials>(_onUnlockWithManualCredentials);
    on<UpdateKeyFilePath>(_onUpdateKeyFilePath);
  }

  final BiometricDataSource biometricDataSource;
  final DatabaseSessionCoordinatorContract databaseSessionCoordinator;

  Future<void> _onInitializeDatabaseUnlock(
    InitializeDatabaseUnlock event,
    Emitter<DatabaseUnlockState> emit,
  ) async {
    _safeEmit(emit, state.copyWith(isLoading: true, clearError: true));
    try {
      final biometricAvailable = await biometricDataSource
          .isBiometricAvailable();
      final bootstrap = await databaseSessionCoordinator.initializeUnlock(
        databasePath: state.databasePath,
        biometricAvailable: biometricAvailable,
      );

      var nextState = state.copyWith(
        isLoading: false,
        keyFilePath: bootstrap.keyFilePath,
        clearKeyFilePath: bootstrap.keyFilePath == null,
        biometricAvailable: bootstrap.biometricAvailable,
        clearError: true,
      );

      if (bootstrap.biometricRequired && bootstrap.biometricAvailable) {
        final biometricsOk = await biometricDataSource.authenticate(
          reason: 'Authenticate to unlock your password database',
        );

        nextState = nextState.copyWith(
          biometricPrompted: true,
          biometricVerified: biometricsOk,
          clearError: true,
        );
        _safeEmit(emit, nextState);

        if (biometricsOk) {
          await _tryStoredCredentialsUnlock(emit);
        } else {
          _safeEmit(
            emit,
            nextState.copyWith(
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
      _safeEmit(
        emit,
        state.copyWith(isLoading: false, errorMessage: e.toString()),
      );
    }
  }

  Future<void> _onRetryBiometricAuthentication(
    RetryBiometricAuthentication event,
    Emitter<DatabaseUnlockState> emit,
  ) async {
    _safeEmit(emit, state.copyWith(isLoading: true, clearError: true));
    final isOk = await biometricDataSource.authenticate(
      reason: 'Authenticate to unlock your password database',
    );

    _safeEmit(
      emit,
      state.copyWith(
        isLoading: false,
        biometricPrompted: true,
        biometricVerified: isOk,
        errorMessage: isOk ? null : 'Biometric authentication failed.',
      ),
    );

    if (isOk) {
      await _tryStoredCredentialsUnlock(emit);
    }
  }

  Future<void> _onUnlockWithManualCredentials(
    UnlockWithManualCredentials event,
    Emitter<DatabaseUnlockState> emit,
  ) async {
    if (_requiresBiometricGate()) {
      _emitError(
        emit,
        'Use biometric authentication before unlocking the database.',
      );
      return;
    }

    _safeEmit(emit, state.copyWith(isLoading: true, clearError: true));

    try {
      await databaseSessionCoordinator.unlockWithManualCredentials(
        databasePath: state.databasePath,
        password: event.password,
        keyFilePath: event.keyFilePath,
      );

      _safeEmit(
        emit,
        state.copyWith(
          isLoading: false,
          keyFilePath: event.keyFilePath,
          unlocked: true,
          clearError: true,
        ),
      );
    } catch (e, st) {
      logError('Manual database unlock failed.', e, st);
      _emitError(
        emit,
        'Unable to unlock database with provided credentials.',
        isLoading: false,
      );
    }
  }

  Future<void> _onUpdateKeyFilePath(
    UpdateKeyFilePath event,
    Emitter<DatabaseUnlockState> emit,
  ) async {
    final normalizedKeyFilePath = event.keyFilePath?.trim();
    final nextKeyFilePath =
        (normalizedKeyFilePath == null || normalizedKeyFilePath.isEmpty)
        ? null
        : normalizedKeyFilePath;
    await databaseSessionCoordinator.updateKeyFilePath(
      databasePath: state.databasePath,
      keyFilePath: nextKeyFilePath,
    );
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
    _safeEmit(emit, state.copyWith(isLoading: true, clearError: true));

    final hasStoredPassword = await databaseSessionCoordinator
        .hasStoredMasterPassword();
    final hasKeyFile =
        state.keyFilePath != null && state.keyFilePath!.isNotEmpty;

    if (!hasStoredPassword && !hasKeyFile) {
      _emitError(
        emit,
        'No saved credentials found. Insert password or select a key file.',
        isLoading: false,
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
        state.copyWith(isLoading: false, unlocked: true, clearError: true),
      );
    } catch (e, st) {
      logError(
        'Stored credentials unlock failed after biometric success.',
        e,
        st,
      );
      _emitError(
        emit,
        'Saved credentials are not valid. Unlock manually.',
        isLoading: false,
      );
    }
  }

  bool _requiresBiometricGate() {
    return state.biometricAvailable && !state.biometricVerified;
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

  void _emitError(
    Emitter<DatabaseUnlockState> emit,
    String message, {
    bool? isLoading,
  }) {
    _safeEmit(
      emit,
      state.copyWith(isLoading: isLoading, errorMessage: message),
    );
  }
}
