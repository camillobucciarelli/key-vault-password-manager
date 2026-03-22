import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/biometric_data_source.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/database_unlock/database_unlock_bloc.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/database_unlock/database_unlock_event.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/database_unlock/database_unlock_state.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/database_selection/database_selection_event.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/database_session_coordinator.dart';
import 'package:password_manager/features/password_manager/domain/models/database_dedup_result.dart';

void main() {
  group('DatabaseUnlockBloc', () {
    late _FakeBiometricDataSource biometric;
    late _FakeDatabaseSessionCoordinator coordinator;
    late DatabaseUnlockBloc bloc;

    setUp(() {
      biometric = _FakeBiometricDataSource();
      coordinator = _FakeDatabaseSessionCoordinator();
      bloc = DatabaseUnlockBloc(
        databasePath: '/tmp/vault.kdbx',
        biometricDataSource: biometric,
        databaseSessionCoordinator: coordinator,
      );
    });

    tearDown(() async {
      await bloc.close();
    });

    test(
      'initializes and unlocks manually when biometric not required',
      () async {
        coordinator.bootstrap = const UnlockBootstrapResult(
          keyFilePath: null,
          biometricRequired: false,
          biometricAvailable: false,
        );

        final states = <DatabaseUnlockState>[];
        final sub = bloc.stream.listen(states.add);

        bloc.add(const InitializeDatabaseUnlock());
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(states.any((s) => s.isLoading), isTrue);
        expect(states.last.biometricVerified, isTrue);

        bloc.add(
          const UnlockWithManualCredentials(
            password: 'secret',
            keyFilePath: null,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(states.last.unlocked, isTrue);
        expect(coordinator.manualUnlockCalls, 1);

        await sub.cancel();
      },
    );

    test(
      'blocks manual unlock if biometric gate is required and not verified',
      () async {
        coordinator.bootstrap = const UnlockBootstrapResult(
          keyFilePath: null,
          biometricRequired: true,
          biometricAvailable: true,
        );
        biometric.authenticateResult = false;

        final states = <DatabaseUnlockState>[];
        final sub = bloc.stream.listen(states.add);

        bloc.add(const InitializeDatabaseUnlock());
        await Future<void>.delayed(const Duration(milliseconds: 20));

        bloc.add(
          const UnlockWithManualCredentials(
            password: 'secret',
            keyFilePath: null,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          states.last.errorMessage,
          contains('Use biometric authentication'),
        );
        expect(coordinator.manualUnlockCalls, 0);

        await sub.cancel();
      },
    );
  });
}

class _FakeBiometricDataSource implements BiometricDataSource {
  bool available = true;
  bool authenticateResult = true;

  @override
  Future<bool> authenticate({required String reason}) async {
    return authenticateResult;
  }

  @override
  Future<bool> isBiometricAvailable() async {
    return available;
  }
}

class _FakeDatabaseSessionCoordinator
    implements DatabaseSessionCoordinatorContract {
  UnlockBootstrapResult bootstrap = const UnlockBootstrapResult(
    keyFilePath: null,
    biometricRequired: false,
    biometricAvailable: false,
  );
  int manualUnlockCalls = 0;

  @override
  Future<UnlockBootstrapResult> initializeUnlock({
    required String databasePath,
    required bool biometricAvailable,
  }) async {
    return bootstrap;
  }

  @override
  Future<bool> hasStoredMasterPassword() async => false;

  @override
  Future<void> unlockWithManualCredentials({
    required String databasePath,
    required String password,
    required String? keyFilePath,
  }) async {
    manualUnlockCalls += 1;
  }

  @override
  Future<void> unlockWithStoredCredentials({
    required String databasePath,
    required String? keyFilePath,
  }) async {}

  @override
  Future<void> updateKeyFilePath({
    required String databasePath,
    required String? keyFilePath,
  }) async {}

  @override
  Future<void> updateBiometricProtection({
    required String databasePath,
    required bool enabled,
  }) async {}

  @override
  Future<DatabaseSelectionSessionResult> checkInitialDatabase() async {
    throw UnimplementedError();
  }

  @override
  Future<DatabaseSelectionSessionResult> createNewDatabase({
    required String databaseFileName,
    required String password,
    String? keyFilePath,
    required bool biometricProtectionEnabled,
    required bool generateKeyFile,
    String? generatedKeyFilePath,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<DatabaseSelectionSessionResult> openRecentDatabase(String path) async {
    throw UnimplementedError();
  }

  @override
  Future<DatabaseSelectionSessionResult> removeRecentDatabase({
    required String path,
    required RecentDatabaseRemovalMode mode,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<DatabaseSelectionSessionResult> resolveDuplicateDecision({
    required DatabaseDuplicatePrompt duplicatePrompt,
    required DatabaseDuplicateResolution decision,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<DatabaseSelectionSessionResult> selectDriveDatabaseLocalCopy({
    required String localPath,
    required String remoteFileId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<DatabaseSelectionSessionResult> selectExistingDatabase({
    required String fileName,
    String? selectedPath,
    List<int>? selectedBytes,
    bool overwriteExisting = false,
  }) async {
    throw UnimplementedError();
  }
}
