import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/secure_data_source.dart';
import 'package:password_manager/features/password_manager/data/services/database_import_service.dart';
import 'package:password_manager/features/password_manager/domain/entities/database_record.dart';
import 'package:password_manager/features/password_manager/domain/entities/database_security_profile.dart';
import 'package:password_manager/features/password_manager/domain/models/apple_autofill_v2_models.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_mapping.dart';
import 'package:password_manager/features/password_manager/domain/models/drive_remote_file.dart';
import 'package:password_manager/features/password_manager/domain/models/sync_conflict.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_registry_repository.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_repository.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_security_repository.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_sync_repository.dart';
import 'package:password_manager/features/password_manager/domain/usecases/get_active_database_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/get_database_security_profile_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/get_registered_databases_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/get_selected_key_file_path_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/link_database_to_drive_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/remove_database_record_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/resolve_database_duplicate_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/save_database_security_profile_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/save_selected_database_path_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/save_selected_key_file_path_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/set_active_database_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/unlock_database_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/upsert_database_record_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/validate_database_usecase.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/database_selection/database_selection_event.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/apple_autofill_v2_coordinator.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/database_session_coordinator.dart';

void main() {
  group('DatabaseSessionCoordinator', () {
    late _FakeDatabaseRepository databaseRepository;
    late _FakeRegistryRepository registryRepository;
    late _FakeSecurityRepository securityRepository;
    late _FakeSyncRepository syncRepository;
    late _FakeSecureDataSource secureDataSource;
    late _FakeAppleAutofillV2Coordinator appleAutofillV2Coordinator;
    late DatabaseSessionCoordinator coordinator;

    setUp(() {
      databaseRepository = _FakeDatabaseRepository();
      registryRepository = _FakeRegistryRepository();
      securityRepository = _FakeSecurityRepository();
      syncRepository = _FakeSyncRepository();
      secureDataSource = _FakeSecureDataSource();
      appleAutofillV2Coordinator = _FakeAppleAutofillV2Coordinator();

      coordinator = DatabaseSessionCoordinator(
        saveSelectedDatabasePathUseCase: SaveSelectedDatabasePathUseCase(
          databaseRepository,
        ),
        getActiveDatabaseUseCase: GetActiveDatabaseUseCase(registryRepository),
        saveSelectedKeyFilePathUseCase: SaveSelectedKeyFilePathUseCase(
          databaseRepository,
        ),
        getSelectedKeyFilePathUseCase: GetSelectedKeyFilePathUseCase(
          databaseRepository,
        ),
        secureDataSource: secureDataSource,
        databaseImportService: DatabaseImportService(
          validateDatabaseUseCase: ValidateDatabaseUseCase(),
        ),
        resolveDatabaseDuplicateUseCase: ResolveDatabaseDuplicateUseCase(
          registryRepository,
        ),
        upsertDatabaseRecordUseCase: UpsertDatabaseRecordUseCase(
          registryRepository,
        ),
        removeDatabaseRecordUseCase: RemoveDatabaseRecordUseCase(
          registryRepository,
        ),
        setActiveDatabaseUseCase: SetActiveDatabaseUseCase(registryRepository),
        getRegisteredDatabasesUseCase: GetRegisteredDatabasesUseCase(
          registryRepository,
        ),
        linkDatabaseToDriveUseCase: LinkDatabaseToDriveUseCase(syncRepository),
        databaseSyncRepository: syncRepository,
        getDatabaseSecurityProfileUseCase: GetDatabaseSecurityProfileUseCase(
          securityRepository,
        ),
        saveDatabaseSecurityProfileUseCase: SaveDatabaseSecurityProfileUseCase(
          securityRepository,
        ),
        unlockDatabaseUseCase: UnlockDatabaseUseCase(),
        appleAutofillV2Coordinator: appleAutofillV2Coordinator,
      );
    });

    test(
      'openRecentDatabase succeeds without duplicate decision prompt',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'db_session_open_recent_',
        );
        addTearDown(() => tempDir.delete(recursive: true));

        final currentPath = '${tempDir.path}/managed.kdbx';
        final currentFile = File(currentPath);

        final content = Uint8List.fromList(<int>[
          0x03,
          0xD9,
          0xA2,
          0x9A,
          0x67,
          0xFB,
          0x4B,
          0xB5,
          ...utf8.encode('fixture'),
        ]);
        await currentFile.writeAsBytes(content, flush: true);
        final fileHash = md5.convert(content).toString();

        registryRepository.records = [
          DatabaseRecord(
            databaseId: 'db-current',
            canonicalPath: currentPath,
            displayName: 'managed.kdbx',
            sourceType: DatabaseSourceType.local,
            fileHash: fileHash,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
          DatabaseRecord(
            databaseId: 'db-other',
            canonicalPath: '${tempDir.path}/other.kdbx',
            displayName: 'other.kdbx',
            sourceType: DatabaseSourceType.local,
            fileHash: fileHash,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
        ];
        secureDataSource.password = 'secret';
        databaseRepository.selectedKeyFilePath = '/tmp/key.key';

        final result = await coordinator.openRecentDatabase(currentPath);

        expect(result.status, DatabaseSessionStatus.success);
        expect(result.path, currentPath);
        expect(result.duplicatePrompt, isNull);
        expect(registryRepository.activeId, 'db-current');
        expect(databaseRepository.selectedDatabasePath, currentPath);
        expect(databaseRepository.selectedKeyFilePath, isNull);
        expect(secureDataSource.password, isNull);
        expect(appleAutofillV2Coordinator.clearCallCount, 1);
      },
    );

    test('removeRecentDatabase clears Apple autofill credentials', () async {
      const currentPath = '/tmp/active.kdbx';
      registryRepository.records = [
        DatabaseRecord(
          databaseId: 'db-current',
          canonicalPath: currentPath,
          displayName: 'active.kdbx',
          sourceType: DatabaseSourceType.local,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ];
      registryRepository.activeId = 'db-current';
      databaseRepository.selectedDatabasePath = currentPath;
      databaseRepository.selectedKeyFilePath = '/tmp/key.key';
      secureDataSource.password = 'secret';

      final result = await coordinator.removeRecentDatabase(
        path: currentPath,
        mode: RecentDatabaseRemovalMode.removeOnly,
      );

      expect(result.status, DatabaseSessionStatus.info);
      expect(registryRepository.records, isEmpty);
      expect(databaseRepository.selectedDatabasePath, '');
      expect(databaseRepository.selectedKeyFilePath, isNull);
      expect(secureDataSource.password, isNull);
      expect(appleAutofillV2Coordinator.clearCallCount, 1);
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
  Future<DatabaseRecord?> findByHash(String fileHash) async {
    for (final record in records) {
      if (record.fileHash == fileHash) {
        return record;
      }
    }
    return null;
  }

  @override
  Future<DatabaseRecord?> findBySource({
    required DatabaseSourceType sourceType,
    required String sourceRef,
  }) async {
    for (final record in records) {
      if (record.sourceType == sourceType && record.sourceRef == sourceRef) {
        return record;
      }
    }
    return null;
  }

  @override
  Future<String?> getActive() async => activeId;

  @override
  Future<DatabaseRecord?> getById(String databaseId) async {
    for (final record in records) {
      if (record.databaseId == databaseId) {
        return record;
      }
    }
    return null;
  }

  @override
  Future<List<DatabaseRecord>> list() async => records;

  @override
  Future<void> remove(String databaseId) async {
    records = records
        .where((record) => record.databaseId != databaseId)
        .toList(growable: false);
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
  final Map<String, DatabaseSecurityProfile> profiles =
      <String, DatabaseSecurityProfile>{};

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

class _FakeAppleAutofillV2Coordinator
    implements AppleAutofillV2CoordinatorContract {
  int clearCallCount = 0;

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
  }) async {}

  @override
  Future<List<AppleAutofillV2PendingAssociation>> readPendingAssociations({
    String? databasePath,
  }) async {
    return const [];
  }
}

class _FakeSyncRepository implements DatabaseSyncRepository {
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
    return DatabaseSyncMapping(
      databasePath: databasePath,
      driveFileId: remoteFileId ?? 'remote-id',
      driveFileName: remoteFileName ?? 'remote.kdbx',
      lastSyncAt: null,
      autoSyncEnabled: true,
    );
  }

  @override
  Future<List<DriveRemoteFile>> listRemoteFiles({String? query}) async {
    return const [];
  }

  @override
  Future<void> moveMappingPath({
    required String fromDatabasePath,
    required String toDatabasePath,
  }) async {}

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
