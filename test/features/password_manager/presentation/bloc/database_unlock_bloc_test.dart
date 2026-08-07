import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/biometric_data_source.dart';
import 'package:password_manager/features/password_manager/domain/errors/database_access_failure.dart';
import 'package:password_manager/features/password_manager/domain/usecases/create_database_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/get_active_database_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/resolve_database_duplicate_usecase.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/database_unlock/database_unlock_bloc.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/database_unlock/database_unlock_event.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/database_unlock/database_unlock_state.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/database_session_coordinator.dart';

import '../coordinators/fake_database_ports.dart';

void main() {
  group('DatabaseUnlockBloc', () {
    late _FakeBiometricDataSource biometric;
    late FakeDatabaseFileRepository fileRepository;
    late FakeDatabaseSessionRepository sessionRepository;
    late FakeDatabaseRegistryRepository registryRepository;
    late FakeDatabaseSecurityRepository securityRepository;
    late FakeDatabaseSyncRepository syncRepository;
    late FakeUnlockDatabaseUseCase unlockUseCase;
    late DatabaseSessionCoordinator coordinator;
    late DatabaseUnlockBloc bloc;

    setUp(() {
      biometric = _FakeBiometricDataSource();
      fileRepository = FakeDatabaseFileRepository();
      sessionRepository = FakeDatabaseSessionRepository();
      registryRepository = FakeDatabaseRegistryRepository();
      securityRepository = FakeDatabaseSecurityRepository();
      syncRepository = FakeDatabaseSyncRepository();
      unlockUseCase = FakeUnlockDatabaseUseCase();
      coordinator = DatabaseSessionCoordinator(
        databaseFileRepository: fileRepository,
        databaseSessionRepository: sessionRepository,
        databaseRegistryRepository: registryRepository,
        databaseSecurityRepository: securityRepository,
        databaseSyncRepository: syncRepository,
        getActiveDatabaseUseCase: GetActiveDatabaseUseCase(registryRepository),
        resolveDatabaseDuplicateUseCase: ResolveDatabaseDuplicateUseCase(
          registryRepository,
        ),
        unlockDatabaseUseCase: unlockUseCase,
        createDatabaseUseCase: CreateDatabaseUseCase(
          databaseFileRepository: fileRepository,
        ),
      );
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
        final states = <DatabaseUnlockState>[];
        final sub = bloc.stream.listen(states.add);

        bloc.add(const InitializeDatabaseUnlock());
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(states.any((s) => s.isLoading), isTrue);
        expect(states.last.phase, UnlockPhase.ready);
        expect(states.last.biometricVerified, isTrue);

        bloc.add(
          const UnlockWithManualCredentials(
            password: 'secret',
            keyFilePath: null,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // C-4: `decrypting` is entered before the await, then `unlocked`.
        expect(states.map((s) => s.phase), contains(UnlockPhase.decrypting));
        expect(states.last.unlocked, isTrue);
        expect(unlockUseCase.callCount, 1);

        await sub.cancel();
      },
    );

    test(
      'retrying failed biometric authentication does not unlock and leaves '
      'the vault untouched',
      () async {
        biometric.available = true;
        biometric.authenticateResult = false;

        final states = <DatabaseUnlockState>[];
        final sub = bloc.stream.listen(states.add);

        bloc.add(const InitializeDatabaseUnlock());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bloc.add(const RetryBiometricAuthentication());
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(states.last.biometricVerified, isFalse);
        expect(unlockUseCase.callCount, 0);

        await sub.cancel();
      },
    );

    test('typed InvalidCredentialsFailure keeps phase ready with copy', () async {
      unlockUseCase.error = const InvalidCredentialsFailure();

      final states = <DatabaseUnlockState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const InitializeDatabaseUnlock());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      bloc.add(
        const UnlockWithManualCredentials(
          password: 'wrong',
          keyFilePath: null,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(states.last.phase, UnlockPhase.ready);
      expect(states.last.failure, isA<InvalidCredentialsFailure>());
      expect(states.last.errorMessage, 'Incorrect master password or key file.');

      await sub.cancel();
    });

    test(
      'typed CorruptDatabaseFailure moves to failure phase, never says '
      'wrong password',
      () async {
        unlockUseCase.error = const CorruptDatabaseFailure('vault.kdbx');

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

        expect(states.last.phase, UnlockPhase.failure);
        expect(states.last.failure, isA<CorruptDatabaseFailure>());
        expect(states.last.errorMessage, isNot(contains('password')));

        await sub.cancel();
      },
    );

    test(
      'a subsequent generic failure clears a previous typed failure '
      '(regression: stale typed field error must not stick around)',
      () async {
        unlockUseCase.error = const InvalidCredentialsFailure();

        final states = <DatabaseUnlockState>[];
        final sub = bloc.stream.listen(states.add);

        bloc.add(const InitializeDatabaseUnlock());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bloc.add(
          const UnlockWithManualCredentials(
            password: 'wrong',
            keyFilePath: null,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(states.last.failure, isA<InvalidCredentialsFailure>());

        unlockUseCase.error = Exception('boom');
        bloc.add(
          const UnlockWithManualCredentials(
            password: 'wrong-again',
            keyFilePath: null,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(states.last.failure, isNull);
        expect(
          states.last.errorMessage,
          'Unable to unlock database with provided credentials.',
        );

        await sub.cancel();
      },
    );

    test('no fake progress: progress stays null through decrypting', () async {
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

      expect(states.every((s) => s.progress == null), isTrue);

      await sub.cancel();
    });
  });

  group('DatabaseUnlockState.copyWith', () {
    test('failure survives when clearError:true and failure is explicit', () {
      const state = DatabaseUnlockState(databasePath: '/tmp/vault.kdbx');
      const someFailure = InvalidCredentialsFailure();

      final result = state.copyWith(clearError: true, failure: someFailure);

      expect(result.failure, someFailure);
    });

    test(
      'keyFilePath survives when clearKeyFilePath:true and keyFilePath is '
      'explicit',
      () {
        const state = DatabaseUnlockState(databasePath: '/tmp/vault.kdbx');

        final result = state.copyWith(
          clearKeyFilePath: true,
          keyFilePath: 'x',
        );

        expect(result.keyFilePath, 'x');
      },
    );
  });
}

class _FakeBiometricDataSource implements BiometricDataSource {
  bool available = false;
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
