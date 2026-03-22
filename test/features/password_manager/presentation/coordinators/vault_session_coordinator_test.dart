import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/secure_data_source.dart';
import 'package:password_manager/features/password_manager/data/services/vault_kdbx_service.dart';
import 'package:password_manager/features/password_manager/domain/entities/database_record.dart';
import 'package:password_manager/features/password_manager/domain/entities/database_security_profile.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_mapping.dart';
import 'package:password_manager/features/password_manager/domain/models/drive_remote_file.dart';
import 'package:password_manager/features/password_manager/domain/models/sync_conflict.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_registry_repository.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_repository.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_security_repository.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_sync_repository.dart';
import 'package:password_manager/features/password_manager/domain/usecases/get_database_security_profile_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/get_registered_databases_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/save_database_security_profile_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/save_selected_database_path_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/save_selected_key_file_path_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/set_active_database_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/upsert_database_record_usecase.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/vault_session_coordinator.dart';

void main() {
  group('VaultSessionCoordinator', () {
    late _FakeDatabaseRepository databaseRepository;
    late _FakeRegistryRepository registryRepository;
    late _FakeSecurityRepository securityRepository;
    late _FakeSyncRepository syncRepository;
    late _FakeSecureDataSource secureDataSource;
    late _FakeVaultKdbxService vaultKdbxService;
    late VaultSessionCoordinator coordinator;

    setUp(() {
      databaseRepository = _FakeDatabaseRepository();
      registryRepository = _FakeRegistryRepository();
      securityRepository = _FakeSecurityRepository();
      syncRepository = _FakeSyncRepository();
      secureDataSource = _FakeSecureDataSource();
      vaultKdbxService = _FakeVaultKdbxService();
      coordinator = VaultSessionCoordinator(
        saveSelectedDatabasePathUseCase: SaveSelectedDatabasePathUseCase(
          databaseRepository,
        ),
        saveSelectedKeyFilePathUseCase: SaveSelectedKeyFilePathUseCase(
          databaseRepository,
        ),
        setActiveDatabaseUseCase: SetActiveDatabaseUseCase(registryRepository),
        secureDataSource: secureDataSource,
        getRegisteredDatabasesUseCase: GetRegisteredDatabasesUseCase(
          registryRepository,
        ),
        upsertDatabaseRecordUseCase: UpsertDatabaseRecordUseCase(
          registryRepository,
        ),
        databaseSyncRepository: syncRepository,
        getDatabaseSecurityProfileUseCase: GetDatabaseSecurityProfileUseCase(
          securityRepository,
        ),
        saveDatabaseSecurityProfileUseCase: SaveDatabaseSecurityProfileUseCase(
          securityRepository,
        ),
        vaultKdbxService: vaultKdbxService,
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

        final result = await coordinator.updateDatabaseSettings(
          DatabaseSettingsUpdateRequest(
            currentDatabasePath: oldFile.path,
            fileName: 'renamed.kdbx',
            keyFilePath: keyFile.path,
            biometricProtectionEnabled: true,
            changePassword: false,
          ),
        );

        expect(result.databasePath.endsWith('renamed.kdbx'), isTrue);
        expect(File(result.databasePath).existsSync(), isTrue);
        expect(oldFile.existsSync(), isFalse);
        expect(syncRepository.movedFrom, oldFile.path);
        expect(syncRepository.movedTo, result.databasePath);
        expect(databaseRepository.selectedDatabasePath, result.databasePath);
        expect(databaseRepository.selectedKeyFilePath, isNotNull);

        final profile = securityRepository.profiles['db-1'];
        expect(profile, isNotNull);
        expect(profile!.keyFilePath, keyFile.path);
        expect(profile.biometricProtectionEnabled, isTrue);
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
              currentPassword: 'old-secret',
              newPassword: 'new-secret',
            ),
          ),
          throwsA(isA<Exception>()),
        );

        expect(oldFile.existsSync(), isTrue);
        expect(File('${tempDir.path}/renamed.kdbx').existsSync(), isFalse);
        expect(syncRepository.movedFrom, isNull);
        expect(syncRepository.movedTo, isNull);
        expect(databaseRepository.selectedDatabasePath, isNull);
        expect(databaseRepository.selectedKeyFilePath, isNull);
        expect(securityRepository.profiles['db-1'], isNull);
        expect(secureDataSource.password, isNull);
      },
    );

    test('changeDatabase clears selected paths and active database', () async {
      databaseRepository.selectedDatabasePath = '/tmp/a.kdbx';
      databaseRepository.selectedKeyFilePath = '/tmp/a.key';
      secureDataSource.password = 'secret';
      registryRepository.activeId = 'db-1';

      await coordinator.changeDatabase(currentDatabasePath: '/tmp/a.kdbx');

      expect(databaseRepository.selectedDatabasePath, '');
      expect(databaseRepository.selectedKeyFilePath, isNull);
      expect(secureDataSource.password, isNull);
      expect(registryRepository.activeId, isNull);
    });
  });
}

class _FakeDatabaseRepository implements DatabaseRepository {
  String? selectedDatabasePath;
  String? selectedKeyFilePath;

  @override
  Future<String?> getSelectedKeyFilePath() async => selectedKeyFilePath;

  @override
  Future<void> saveSelectedDatabasePath(String path) async {
    selectedDatabasePath = path;
  }

  @override
  Future<void> saveSelectedKeyFilePath(String? path) async {
    selectedKeyFilePath = path;
  }
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
    profiles[profile.databaseId] = profile;
  }
}

class _FakeSecureDataSource implements SecureDataSource {
  String? password;

  @override
  Future<void> clearMasterPassword() async {
    password = null;
  }

  @override
  Future<String?> getMasterPassword() async => password;

  @override
  Future<void> saveMasterPassword(String password) async {
    this.password = password;
  }
}

class _FakeVaultKdbxService extends VaultKdbxService {
  bool shouldThrowOnChangeMasterPassword = false;

  @override
  Future<void> changeMasterPassword({
    required String databasePath,
    required String currentPassword,
    String? keyFilePath,
    required String newPassword,
  }) async {
    if (shouldThrowOnChangeMasterPassword) {
      throw Exception('Unable to change password.');
    }
  }
}

class _FakeSyncRepository implements DatabaseSyncRepository {
  String? movedFrom;
  String? movedTo;

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
    movedFrom = fromDatabasePath;
    movedTo = toDatabasePath;
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
