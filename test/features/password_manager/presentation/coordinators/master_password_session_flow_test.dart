import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/errors/database_access_failure.dart';
import 'package:password_manager/features/password_manager/domain/usecases/create_database_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/get_active_database_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/resolve_database_duplicate_usecase.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/database_session_coordinator.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/master_password_session.dart';

import 'fake_database_ports.dart';

// spec-011 FR-1/FR-2: the DatabaseSessionCoordinator populates the in-memory
// session-secret holder on successful unlock and clears it when the unlock
// fails. (Clear-on-lock/switch is covered by vault_session_coordinator_test.)
void main() {
  late FakeDatabaseFileRepository fileRepository;
  late FakeDatabaseSessionRepository sessionRepository;
  late FakeDatabaseRegistryRepository registryRepository;
  late FakeDatabaseSecurityRepository securityRepository;
  late FakeDatabaseSyncRepository syncRepository;
  late FakeUnlockDatabaseUseCase unlockUseCase;
  late MasterPasswordSession masterPasswordSession;
  late DatabaseSessionCoordinator coordinator;

  setUp(() {
    fileRepository = FakeDatabaseFileRepository();
    sessionRepository = FakeDatabaseSessionRepository();
    registryRepository = FakeDatabaseRegistryRepository();
    securityRepository = FakeDatabaseSecurityRepository();
    syncRepository = FakeDatabaseSyncRepository();
    unlockUseCase = FakeUnlockDatabaseUseCase();
    masterPasswordSession = MasterPasswordSession();
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
      masterPasswordSession: masterPasswordSession,
    );
  });

  test('FR-1: a successful manual unlock populates the session holder', () async {
    expect(masterPasswordSession.value, isNull);

    await coordinator.unlockWithManualCredentials(
      databasePath: '/tmp/vault.kdbx',
      password: 'correct horse',
      keyFilePath: null,
    );

    expect(masterPasswordSession.value, 'correct horse');
  });

  test('FR-2: a failed manual unlock leaves no live session secret', () async {
    unlockUseCase.error = const InvalidCredentialsFailure();

    await expectLater(
      coordinator.unlockWithManualCredentials(
        databasePath: '/tmp/vault.kdbx',
        password: 'wrong',
        keyFilePath: null,
      ),
      throwsA(isA<InvalidCredentialsFailure>()),
    );

    expect(masterPasswordSession.value, isNull);
  });

  test('FR-2: a failed unlock clears a secret left by a prior session', () async {
    masterPasswordSession.set('stale-from-previous-vault');
    unlockUseCase.error = const InvalidCredentialsFailure();

    await expectLater(
      coordinator.unlockWithManualCredentials(
        databasePath: '/tmp/vault.kdbx',
        password: 'wrong',
        keyFilePath: null,
      ),
      throwsA(isA<InvalidCredentialsFailure>()),
    );

    expect(masterPasswordSession.value, isNull);
  });
}
