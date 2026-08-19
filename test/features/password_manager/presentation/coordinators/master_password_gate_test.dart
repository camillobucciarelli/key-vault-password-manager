import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/entities/database_record.dart';
import 'package:password_manager/features/password_manager/domain/entities/database_security_profile.dart';
import 'package:password_manager/features/password_manager/domain/models/recent_database_removal_mode.dart';
import 'package:password_manager/features/password_manager/domain/usecases/create_database_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/get_active_database_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/resolve_database_duplicate_usecase.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/database_session_coordinator.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/master_password_session.dart';

import 'fake_database_ports.dart';

// spec-011 FR-3 (gate) and FR-5 (erase). The keystore biometric credential is
// written only when biometric protection is enabled for the target database,
// and removed when it is disabled or the database is unregistered.
void main() {
  late FakeDatabaseFileRepository fileRepository;
  late FakeDatabaseSessionRepository sessionRepository;
  late FakeDatabaseRegistryRepository registryRepository;
  late FakeDatabaseSecurityRepository securityRepository;
  late FakeDatabaseSyncRepository syncRepository;
  late FakeUnlockDatabaseUseCase unlockUseCase;
  late MasterPasswordSession masterPasswordSession;
  late DatabaseSessionCoordinator coordinator;

  const path = '/tmp/vault.kdbx';
  const id = 'db-1';

  void registerDatabase({required bool biometricEnabled}) {
    registryRepository.records = [
      DatabaseRecord(
        databaseId: id,
        canonicalPath: path,
        displayName: 'vault.kdbx',
        sourceType: DatabaseSourceType.local,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ];
    registryRepository.activeId = id;
    securityRepository.profiles[id] = DatabaseSecurityProfile(
      databaseId: id,
      biometricProtectionEnabled: biometricEnabled,
    );
  }

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

  group('FR-3 unlock write gate', () {
    test('biometrics ON persists the credential under the database key',
        () async {
      registerDatabase(biometricEnabled: true);

      await coordinator.unlockWithManualCredentials(
        databasePath: path,
        password: 'secret',
        keyFilePath: null,
      );

      expect(sessionRepository.masterPasswords[id], 'secret');
    });

    test('biometrics OFF never touches the keystore (AC-1)', () async {
      registerDatabase(biometricEnabled: false);

      await coordinator.unlockWithManualCredentials(
        databasePath: path,
        password: 'secret',
        keyFilePath: null,
      );

      expect(sessionRepository.masterPasswords, isEmpty);
      // The in-memory session secret is still live regardless of the gate.
      expect(masterPasswordSession.value, 'secret');
    });
  });

  group('FR-5 erase', () {
    test('enabling biometrics stores the live session secret', () async {
      registerDatabase(biometricEnabled: false);
      masterPasswordSession.set('secret');

      await coordinator.updateBiometricProtection(
        databasePath: path,
        enabled: true,
      );

      expect(sessionRepository.masterPasswords[id], 'secret');
    });

    test('disabling biometrics erases the stored credential immediately',
        () async {
      registerDatabase(biometricEnabled: true);
      sessionRepository.masterPasswords[id] = 'secret';

      await coordinator.updateBiometricProtection(
        databasePath: path,
        enabled: false,
      );

      expect(sessionRepository.masterPasswords.containsKey(id), isFalse);
    });

    test('unregistering a database deletes its stored credential', () async {
      registerDatabase(biometricEnabled: true);
      sessionRepository.masterPasswords[id] = 'secret';

      await coordinator.removeRecentDatabase(
        path: path,
        mode: RecentDatabaseRemovalMode.removeOnly,
      );

      expect(sessionRepository.masterPasswords.containsKey(id), isFalse);
    });
  });
}
