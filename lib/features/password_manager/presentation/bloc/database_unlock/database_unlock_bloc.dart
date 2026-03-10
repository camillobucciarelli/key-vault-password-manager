import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:loggy/loggy.dart';

import '../../../data/datasources/biometric_data_source.dart';
import '../../../data/datasources/secure_data_source.dart';
import '../../../domain/usecases/get_biometric_protection_enabled_usecase.dart';
import '../../../domain/usecases/get_selected_key_file_path_usecase.dart';
import '../../../domain/usecases/save_selected_key_file_path_usecase.dart';
import '../../../domain/usecases/unlock_database_usecase.dart';
import 'database_unlock_event.dart';
import 'database_unlock_state.dart';

class DatabaseUnlockBloc
    extends Bloc<DatabaseUnlockEvent, DatabaseUnlockState> {
  final GetSelectedKeyFilePathUseCase getSelectedKeyFilePathUseCase;
  final SaveSelectedKeyFilePathUseCase saveSelectedKeyFilePathUseCase;
  final GetBiometricProtectionEnabledUseCase
  getBiometricProtectionEnabledUseCase;
  final BiometricDataSource biometricDataSource;
  final SecureDataSource secureDataSource;
  final UnlockDatabaseUseCase unlockDatabaseUseCase;

  DatabaseUnlockBloc({
    required String databasePath,
    required this.getSelectedKeyFilePathUseCase,
    required this.saveSelectedKeyFilePathUseCase,
    required this.getBiometricProtectionEnabledUseCase,
    required this.biometricDataSource,
    required this.secureDataSource,
    required this.unlockDatabaseUseCase,
  }) : super(DatabaseUnlockState.initial(databasePath: databasePath)) {
    on<InitializeDatabaseUnlock>(_onInitializeDatabaseUnlock);
    on<RetryBiometricAuthentication>(_onRetryBiometricAuthentication);
    on<UnlockWithManualCredentials>(_onUnlockWithManualCredentials);
    on<UpdateKeyFilePath>(_onUpdateKeyFilePath);
  }

  Future<void> _onInitializeDatabaseUnlock(
    InitializeDatabaseUnlock event,
    Emitter<DatabaseUnlockState> emit,
  ) async {
    _safeEmit(emit, state.copyWith(isLoading: true, clearError: true));
    try {
      final savedKeyFilePath = await getSelectedKeyFilePathUseCase();
      final isBiometricEnabled = await getBiometricProtectionEnabledUseCase();
      final biometricsAvailable = await biometricDataSource
          .isBiometricAvailable();

      var nextState = state.copyWith(
        isLoading: false,
        keyFilePath: savedKeyFilePath,
        biometricAvailable: biometricsAvailable,
        clearError: true,
      );

      if (isBiometricEnabled && biometricsAvailable) {
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
          logWarning('Initial biometric authentication failed.');
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
          biometricPrompted: isBiometricEnabled,
          biometricVerified: !isBiometricEnabled || !biometricsAvailable,
          errorMessage: isBiometricEnabled && !biometricsAvailable
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

    if (!isOk) {
      logWarning('Biometric retry authentication failed.');
    }

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
      await unlockDatabaseUseCase(
        databasePath: state.databasePath,
        password: event.password,
        keyFilePath: event.keyFilePath,
      );

      await saveSelectedKeyFilePathUseCase(event.keyFilePath);
      await secureDataSource.saveMasterPassword(event.password);

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
    await saveSelectedKeyFilePathUseCase(event.keyFilePath);
    _safeEmit(
      emit,
      state.copyWith(keyFilePath: event.keyFilePath, clearError: true),
    );
  }

  Future<void> _tryStoredCredentialsUnlock(
    Emitter<DatabaseUnlockState> emit,
  ) async {
    _safeEmit(emit, state.copyWith(isLoading: true, clearError: true));
    final storedPassword = await secureDataSource.getMasterPassword();

    if ((storedPassword == null || storedPassword.isEmpty) &&
        (state.keyFilePath == null || state.keyFilePath!.isEmpty)) {
      _emitError(
        emit,
        'No saved credentials found. Insert password or select a key file.',
        isLoading: false,
      );
      return;
    }

    try {
      await unlockDatabaseUseCase(
        databasePath: state.databasePath,
        password: storedPassword ?? '',
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
