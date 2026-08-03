import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kdbx/kdbx.dart';
import 'package:password_manager/features/password_manager/data/datasources/secure_data_source.dart';
import 'package:password_manager/features/password_manager/data/services/vault_kdbx_service.dart';
import 'package:password_manager/features/password_manager/domain/entities/database_record.dart';
import 'package:password_manager/features/password_manager/domain/entities/database_security_profile.dart';
import 'package:password_manager/features/password_manager/domain/models/apple_autofill_v2_models.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_mapping.dart';
import 'package:password_manager/features/password_manager/domain/models/drive_remote_file.dart';
import 'package:password_manager/features/password_manager/domain/models/sync_conflict.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';
import 'package:password_manager/features/password_manager/data/datasources/local_data_source.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_registry_repository.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_security_repository.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_sync_repository.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/apple_autofill_v2_coordinator.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/vault_session_coordinator.dart';

void main() {
  group('VaultSessionCoordinator', () {
    late _FakeLocalDataSource localDataSource;
    late _FakeRegistryRepository registryRepository;
    late _FakeSecurityRepository securityRepository;
    late _FakeSyncRepository syncRepository;
    late _FakeSecureDataSource secureDataSource;
    late _FakeVaultKdbxService vaultKdbxService;
    late _FakeAppleAutofillV2Coordinator appleAutofillV2Coordinator;
    late VaultSessionCoordinator coordinator;

    setUp(() {
      localDataSource = _FakeLocalDataSource();
      registryRepository = _FakeRegistryRepository();
      securityRepository = _FakeSecurityRepository();
      syncRepository = _FakeSyncRepository();
      secureDataSource = _FakeSecureDataSource();
      vaultKdbxService = _FakeVaultKdbxService();
      appleAutofillV2Coordinator = _FakeAppleAutofillV2Coordinator();
      coordinator = VaultSessionCoordinator(
        localDataSource: localDataSource,
        databaseRegistryRepository: registryRepository,
        databaseSecurityRepository: securityRepository,
        secureDataSource: secureDataSource,
        databaseSyncRepository: syncRepository,
        vaultKdbxService: vaultKdbxService,
        appleAutofillV2Coordinator: appleAutofillV2Coordinator,
      );
    });

    test(
      'updateDatabaseSettings renames database and updates mapping/profile',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'vault_session_test_',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final oldFile = File('${tempDir.path}/old.kdbx');
        await oldFile.writeAsBytes(const [1, 2, 3], flush: true);
        final keyFile = File('${tempDir.path}/main.key');
        await keyFile.writeAsBytes(const [4, 5, 6], flush: true);

        registryRepository.records = [
          DatabaseRecord(
            databaseId: 'db-1',
            canonicalPath: oldFile.path,
            displayName: 'old.kdbx',
            sourceType: DatabaseSourceType.local,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ];
        secureDataSource.password = 'secret';

        final result = await coordinator.updateDatabaseSettings(
          DatabaseSettingsUpdateRequest(
            currentDatabasePath: oldFile.path,
            fileName: 'renamed.kdbx',
            keyFilePath: keyFile.path,
            biometricProtectionEnabled: true,
            changePassword: false,
            inactivityLockTimeoutSeconds: null,
          ),
        );

        expect(result.databasePath.endsWith('renamed.kdbx'), isTrue);
        expect(File(result.databasePath).existsSync(), isTrue);
        expect(oldFile.existsSync(), isFalse);
        expect(syncRepository.movedFrom, oldFile.path);
        expect(syncRepository.movedTo, result.databasePath);
        expect(localDataSource.selectedDatabasePath, result.databasePath);
        expect(localDataSource.selectedKeyFilePath, isNotNull);

        final profile = securityRepository.profiles['db-1'];
        expect(profile, isNotNull);
        expect(profile!.keyFilePath, keyFile.path);
        expect(profile.biometricProtectionEnabled, isTrue);
        expect(vaultKdbxService.currentKeyFilePath, isNull);
        expect(vaultKdbxService.newKeyFilePath, keyFile.path);
        expect(vaultKdbxService.currentPassword, 'secret');
        expect(vaultKdbxService.newPassword, 'secret');
        expect(vaultKdbxService.finalizeCount, 1);
      },
    );

    test(
      'updateDatabaseSettings does not persist profile paths when password change fails',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'vault_session_test_',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final oldFile = File('${tempDir.path}/old.kdbx');
        await oldFile.writeAsBytes(const [1, 2, 3], flush: true);
        final keyFile = File('${tempDir.path}/main.key');
        await keyFile.writeAsBytes(const [4, 5, 6], flush: true);

        registryRepository.records = [
          DatabaseRecord(
            databaseId: 'db-1',
            canonicalPath: oldFile.path,
            displayName: 'old.kdbx',
            sourceType: DatabaseSourceType.local,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ];
        vaultKdbxService.shouldThrowOnChangeMasterPassword = true;

        await expectLater(
          coordinator.updateDatabaseSettings(
            DatabaseSettingsUpdateRequest(
              currentDatabasePath: oldFile.path,
              fileName: 'renamed.kdbx',
              keyFilePath: keyFile.path,
              biometricProtectionEnabled: true,
              changePassword: true,
              inactivityLockTimeoutSeconds: null,
              currentPassword: 'old-secret',
              newPassword: 'new-secret',
            ),
          ),
          throwsA(isA<Exception>()),
        );

        expect(oldFile.existsSync(), isTrue);
        expect(File('${tempDir.path}/renamed.kdbx').existsSync(), isFalse);
        expect(syncRepository.moves, [
          (oldFile.path, '${tempDir.path}/renamed.kdbx'),
          ('${tempDir.path}/renamed.kdbx', oldFile.path),
        ]);
        expect(localDataSource.selectedDatabasePath, oldFile.path);
        expect(localDataSource.selectedKeyFilePath, isNull);
        expect(securityRepository.profiles['db-1'], isNull);
        expect(secureDataSource.password, isNull);
      },
    );

    test('mapping failure rolls database rename back', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'vault_mapping_rollback_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final oldFile = File('${tempDir.path}/old.kdbx');
      await oldFile.writeAsBytes(const [1]);
      registryRepository.records = [_recordForTest('db-1', oldFile.path)];
      secureDataSource.password = 'secret';
      syncRepository.failNextMove = true;

      await expectLater(
        coordinator.updateDatabaseSettings(
          DatabaseSettingsUpdateRequest(
            currentDatabasePath: oldFile.path,
            fileName: 'renamed.kdbx',
            keyFilePath: null,
            biometricProtectionEnabled: true,
            changePassword: false,
            inactivityLockTimeoutSeconds: null,
          ),
        ),
        throwsException,
      );

      expect(await oldFile.exists(), isTrue);
      expect(await File('${tempDir.path}/renamed.kdbx').exists(), isFalse);
      expect(registryRepository.records.single.canonicalPath, oldFile.path);
      expect(vaultKdbxService.currentPassword, isNull);
    });

    test('does not remove the last unlock credential', () async {
      const databasePath = '/tmp/key-only.kdbx';
      registryRepository.records = [
        DatabaseRecord(
          databaseId: 'db-key-only',
          canonicalPath: databasePath,
          displayName: 'key-only.kdbx',
          sourceType: DatabaseSourceType.local,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ];
      localDataSource.selectedKeyFilePath = '/tmp/current.key';
      secureDataSource.password = '';

      await expectLater(
        coordinator.updateDatabaseSettings(
          const DatabaseSettingsUpdateRequest(
            currentDatabasePath: databasePath,
            fileName: 'key-only.kdbx',
            keyFilePath: null,
            biometricProtectionEnabled: false,
            changePassword: false,
            inactivityLockTimeoutSeconds: null,
          ),
        ),
        throwsException,
      );

      expect(vaultKdbxService.currentPassword, isNull);
      expect(localDataSource.selectedKeyFilePath, '/tmp/current.key');
    });

    test(
      'profile failure rolls back credentials and pending key metadata',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'vault_session_rollback_test_',
        );
        addTearDown(() => tempDir.delete(recursive: true));
        final databasePath = '${tempDir.path}/vault.kdbx';
        final currentKey = '${tempDir.path}/current.key';
        final pendingKey = '${tempDir.path}/pending.key';
        await File(databasePath).writeAsBytes(const [1]);
        await File(currentKey).writeAsBytes(const [2]);
        await File(pendingKey).writeAsBytes(const [3]);
        registryRepository.records = [_recordForTest('db-1', databasePath)];
        securityRepository.profiles['db-1'] = DatabaseSecurityProfile(
          databaseId: 'db-1',
          keyFilePath: currentKey,
        );
        localDataSource.selectedDatabasePath = databasePath;
        localDataSource.selectedKeyFilePath = currentKey;
        secureDataSource.password = 'old-secret';
        securityRepository.failNextSave = true;

        await expectLater(
          coordinator.updateDatabaseSettings(
            DatabaseSettingsUpdateRequest(
              currentDatabasePath: databasePath,
              fileName: 'vault.kdbx',
              keyFilePath: pendingKey,
              biometricProtectionEnabled: true,
              changePassword: true,
              inactivityLockTimeoutSeconds: 60,
              currentPassword: 'old-secret',
              newPassword: 'new-secret',
            ),
          ),
          throwsException,
        );

        expect(vaultKdbxService.rollbackCount, 1);
        expect(secureDataSource.password, 'old-secret');
        expect(localDataSource.selectedKeyFilePath, currentKey);
        expect(securityRepository.profiles['db-1']!.keyFilePath, currentKey);
        expect(await File(pendingKey).exists(), isTrue);
      },
    );

    test('secure storage failure rolls back credential transaction', () async {
      const databasePath = '/tmp/vault.kdbx';
      registryRepository.records = [_recordForTest('db-1', databasePath)];
      localDataSource.selectedDatabasePath = databasePath;
      secureDataSource.password = 'old-secret';
      secureDataSource.failNextSave = true;

      await expectLater(
        coordinator.updateDatabaseSettings(
          const DatabaseSettingsUpdateRequest(
            currentDatabasePath: databasePath,
            fileName: 'vault.kdbx',
            keyFilePath: null,
            biometricProtectionEnabled: true,
            changePassword: true,
            inactivityLockTimeoutSeconds: null,
            currentPassword: 'old-secret',
            newPassword: 'new-secret',
          ),
        ),
        throwsException,
      );

      expect(vaultKdbxService.rollbackCount, 1);
      expect(secureDataSource.password, 'old-secret');
      expect(localDataSource.selectedDatabasePath, databasePath);
    });

    test('profile failure reopens with old credentials, not new', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'vault_session_real_rollback_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final databasePath = '${tempDir.path}/vault.kdbx';
      await _createTestDatabase(databasePath, 'old-secret');
      registryRepository.records = [_recordForTest('db-1', databasePath)];
      localDataSource.selectedDatabasePath = databasePath;
      secureDataSource.password = 'old-secret';
      securityRepository.failNextSave = true;
      final realService = VaultKdbxService();
      coordinator = VaultSessionCoordinator(
        localDataSource: localDataSource,
        databaseRegistryRepository: registryRepository,
        databaseSecurityRepository: securityRepository,
        secureDataSource: secureDataSource,
        databaseSyncRepository: syncRepository,
        vaultKdbxService: realService,
        appleAutofillV2Coordinator: appleAutofillV2Coordinator,
      );

      await expectLater(
        coordinator.updateDatabaseSettings(
          DatabaseSettingsUpdateRequest(
            currentDatabasePath: databasePath,
            fileName: 'vault.kdbx',
            keyFilePath: null,
            biometricProtectionEnabled: true,
            changePassword: true,
            inactivityLockTimeoutSeconds: null,
            currentPassword: 'old-secret',
            newPassword: 'new-secret',
          ),
        ),
        throwsException,
      );

      await expectLater(
        realService.loadVault(
          databasePath: databasePath,
          password: 'old-secret',
        ),
        completes,
      );
      await expectLater(
        realService.loadVault(
          databasePath: databasePath,
          password: 'new-secret',
        ),
        throwsA(anything),
      );
    });

    test('protected key paths cover current and shared profiles', () async {
      const shared = '/tmp/shared.key';
      registryRepository.records = [
        _recordForTest('db-1', '/tmp/a.kdbx'),
        _recordForTest('db-2', '/tmp/b.kdbx'),
      ];
      securityRepository.profiles['db-1'] = const DatabaseSecurityProfile(
        databaseId: 'db-1',
        keyFilePath: shared,
      );
      securityRepository.profiles['db-2'] = const DatabaseSecurityProfile(
        databaseId: 'db-2',
        keyFilePath: shared,
      );

      expect(await coordinator.getProtectedKeyFilePaths(), {shared});
      expect(await coordinator.getPersistedKeyFilePath('/tmp/a.kdbx'), shared);
    });

    test(
      'changeDatabase clears selected paths, active database, and master password',
      () async {
        localDataSource.selectedDatabasePath = '/tmp/a.kdbx';
        localDataSource.selectedKeyFilePath = '/tmp/a.key';
        secureDataSource.password = 'secret';
        registryRepository.activeId = 'db-1';

        await coordinator.changeDatabase(currentDatabasePath: '/tmp/a.kdbx');

        expect(localDataSource.selectedDatabasePath, '');
        expect(localDataSource.selectedKeyFilePath, isNull);
        expect(secureDataSource.password, isNull);
        expect(registryRepository.activeId, isNull);
        expect(appleAutofillV2Coordinator.clearCallCount, 1);
      },
    );

    test('lockVault clears Apple autofill credentials', () async {
      localDataSource.selectedDatabasePath = '/tmp/a.kdbx';
      secureDataSource.password = 'secret';

      await coordinator.lockVault(currentDatabasePath: '/tmp/a.kdbx');

      expect(localDataSource.selectedDatabasePath, '/tmp/a.kdbx');
      expect(secureDataSource.password, isNull);
      expect(appleAutofillV2Coordinator.clearCallCount, 1);
    });

    test(
      'getInactivityLockTimeoutForPath returns correct timeout when database is registered',
      () async {
        const databasePath = '/tmp/test.kdbx';
        registryRepository.records = [
          DatabaseRecord(
            databaseId: 'db-1',
            canonicalPath: databasePath,
            displayName: 'test.kdbx',
            sourceType: DatabaseSourceType.local,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ];
        securityRepository.profiles['db-1'] = DatabaseSecurityProfile(
          databaseId: 'db-1',
          inactivityLockTimeoutSeconds: 300,
        );

        final result = await coordinator.getInactivityLockTimeoutForPath(
          databasePath: databasePath,
        );

        expect(result, 300);
      },
    );

    test(
      'getInactivityLockTimeoutForPath returns null when database path is empty',
      () async {
        registryRepository.records = [
          DatabaseRecord(
            databaseId: 'db-1',
            canonicalPath: '/tmp/test.kdbx',
            displayName: 'test.kdbx',
            sourceType: DatabaseSourceType.local,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ];

        final result = await coordinator.getInactivityLockTimeoutForPath(
          databasePath: '',
        );

        expect(result, isNull);
      },
    );
  });
}

DatabaseRecord _recordForTest(String id, String path) => DatabaseRecord(
  databaseId: id,
  canonicalPath: path,
  displayName: path.split('/').last,
  sourceType: DatabaseSourceType.local,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Future<void> _createTestDatabase(String path, String password) async {
  final file = KdbxFormat().create(
    Credentials.composite(ProtectedValue.fromString(password), null),
    'Test',
  );
  await File(path).writeAsBytes(await file.save(), flush: true);
}

class _FakeLocalDataSource implements LocalDataSource {
  String? selectedDatabasePath;
  String? selectedKeyFilePath;

  @override
  Future<void> cacheDatabasePath(String path) async {
    selectedDatabasePath = path;
  }

  @override
  Future<String?> getCachedKeyFilePath() async => selectedKeyFilePath;

  @override
  Future<void> cacheKeyFilePath(String? path) async {
    selectedKeyFilePath = path;
  }

  @override
  Future<bool> getAutofillPromptSeen() async => false;

  @override
  Future<void> setAutofillPromptSeen(bool seen) async {}
}

class _FakeRegistryRepository implements DatabaseRegistryRepository {
  List<DatabaseRecord> records = [];
  String? activeId;

  @override
  Future<DatabaseRecord?> findByHash(String fileHash) async => null;

  @override
  Future<DatabaseRecord?> findBySource({
    required DatabaseSourceType sourceType,
    required String sourceRef,
  }) async => null;

  @override
  Future<String?> getActive() async => activeId;

  @override
  Future<DatabaseRecord?> getById(String databaseId) async {
    return records
        .where((record) => record.databaseId == databaseId)
        .firstOrNull;
  }

  @override
  Future<List<DatabaseRecord>> list() async => records;

  @override
  Future<void> remove(String databaseId) async {
    records = records
        .where((record) => record.databaseId != databaseId)
        .toList();
  }

  @override
  Future<void> setActive(String? databaseId) async {
    activeId = databaseId;
  }

  @override
  Future<void> upsert(DatabaseRecord record) async {
    records = [
      ...records.where((item) => item.databaseId != record.databaseId),
      record,
    ];
  }
}

class _FakeSecurityRepository implements DatabaseSecurityRepository {
  final Map<String, DatabaseSecurityProfile> profiles = {};
  bool failNextSave = false;

  @override
  Future<DatabaseSecurityProfile?> getProfile(String databaseId) async {
    return profiles[databaseId];
  }

  @override
  Future<void> removeProfile(String databaseId) async {
    profiles.remove(databaseId);
  }

  @override
  Future<void> saveProfile(DatabaseSecurityProfile profile) async {
    if (failNextSave) {
      failNextSave = false;
      throw Exception('Profile write failed.');
    }
    profiles[profile.databaseId] = profile;
  }
}

class _FakeSecureDataSource implements SecureDataSource {
  String? password;
  bool failNextSave = false;

  @override
  Future<void> clearMasterPassword() async {
    password = null;
  }

  @override
  Future<String?> getMasterPassword() async => password;

  @override
  Future<void> saveMasterPassword(String password) async {
    if (failNextSave) {
      failNextSave = false;
      throw Exception('Secure storage write failed.');
    }
    this.password = password;
  }
}

class _FakeVaultKdbxService extends VaultKdbxService {
  bool shouldThrowOnChangeMasterPassword = false;
  String? currentKeyFilePath;
  String? newKeyFilePath;
  String? currentPassword;
  String? newPassword;
  int rollbackCount = 0;
  int finalizeCount = 0;

  @override
  Future<KdbxCredentialChange> beginCredentialChange({
    required String databasePath,
    required String currentPassword,
    String? currentKeyFilePath,
    required String newPassword,
    String? newKeyFilePath,
  }) async {
    if (shouldThrowOnChangeMasterPassword) {
      throw Exception('Unable to change password.');
    }
    this.currentKeyFilePath = currentKeyFilePath;
    this.newKeyFilePath = newKeyFilePath;
    this.currentPassword = currentPassword;
    this.newPassword = newPassword;
    return KdbxCredentialChange(
      databasePath: databasePath,
      backupPath: '$databasePath.test-backup',
    );
  }

  @override
  Future<void> finalizeCredentialChange(KdbxCredentialChange change) async {
    finalizeCount += 1;
  }

  @override
  Future<void> rollbackCredentialChange(KdbxCredentialChange change) async {
    rollbackCount += 1;
  }
}

class _FakeAppleAutofillV2Coordinator
    implements AppleAutofillV2CoordinatorContract {
  int clearCallCount = 0;
  int publishCallCount = 0;

  @override
  Future<void> clearCredentials({String? databasePath}) async {
    clearCallCount += 1;
  }

  @override
  Future<void> clearPendingAssociations({List<String>? ids}) async {}

  @override
  Future<void> publishVault({
    required String databasePath,
    required List<VaultEntry> entries,
  }) async {
    publishCallCount += 1;
  }

  @override
  Future<List<AppleAutofillV2PendingAssociation>> readPendingAssociations({
    String? databasePath,
  }) async {
    return const [];
  }
}

class _FakeSyncRepository implements DatabaseSyncRepository {
  String? movedFrom;
  String? movedTo;
  final List<(String, String)> moves = [];
  bool failNextMove = false;

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<Uint8List> downloadRemoteFile(String fileId) async {
    throw UnimplementedError();
  }

  @override
  Future<DatabaseSyncMapping?> getMapping(String databasePath) async => null;

  @override
  Future<bool> isConnected() async => false;

  @override
  Future<DatabaseSyncMapping> linkDatabaseToDrive({
    required String databasePath,
    String? remoteFileId,
    String? remoteFileName,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<DriveRemoteFile>> listRemoteFiles({String? query}) async {
    return const [];
  }

  @override
  Future<void> moveMappingPath({
    required String fromDatabasePath,
    required String toDatabasePath,
  }) async {
    if (failNextMove) {
      failNextMove = false;
      throw Exception('Mapping move failed.');
    }
    movedFrom = fromDatabasePath;
    movedTo = toDatabasePath;
    moves.add((fromDatabasePath, toDatabasePath));
  }

  @override
  Future<void> removeMapping(String databasePath) async {}

  @override
  Future<void> setAutoSync(String databasePath, bool enabled) async {}

  @override
  Future<SyncNowResult> syncNow(
    String databasePath, {
    SyncConflictResolution? resolution,
  }) async {
    return const SyncNowSuccess();
  }
}
