import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/local_data_source.dart';
import 'package:password_manager/features/password_manager/data/datasources/secure_data_source.dart';
import 'package:password_manager/features/password_manager/data/services/database_import_service.dart';
import 'package:password_manager/features/password_manager/domain/entities/database_record.dart';
import 'package:password_manager/features/password_manager/domain/entities/database_security_profile.dart';
import 'package:password_manager/features/password_manager/domain/models/apple_autofill_v2_models.dart';
import 'package:password_manager/features/password_manager/domain/models/database_dedup_result.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_mapping.dart';
import 'package:password_manager/features/password_manager/domain/models/drive_remote_file.dart';
import 'package:password_manager/features/password_manager/domain/models/sync_conflict.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_registry_repository.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_security_repository.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_sync_repository.dart';
import 'package:password_manager/features/password_manager/domain/usecases/get_active_database_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/resolve_database_duplicate_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/unlock_database_usecase.dart';
import 'package:password_manager/features/password_manager/domain/usecases/validate_database_usecase.dart';
import 'package:password_manager/features/password_manager/presentation/bloc/database_selection/database_selection_event.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/apple_autofill_v2_coordinator.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/database_session_coordinator.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DatabaseSessionCoordinator', () {
    late Directory tempDir;
    late _FakeLocalDataSource localDataSource;
    late _FakeRegistryRepository registryRepository;
    late _FakeSecurityRepository securityRepository;
    late _FakeSyncRepository syncRepository;
    late _FakeSecureDataSource secureDataSource;
    late _FakeAppleAutofillV2Coordinator appleAutofillV2Coordinator;
    late DatabaseImportService databaseImportService;
    late DatabaseSessionCoordinator coordinator;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('db_session_test_');
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);

      localDataSource = _FakeLocalDataSource();
      registryRepository = _FakeRegistryRepository();
      securityRepository = _FakeSecurityRepository();
      syncRepository = _FakeSyncRepository();
      secureDataSource = _FakeSecureDataSource();
      appleAutofillV2Coordinator = _FakeAppleAutofillV2Coordinator();
      databaseImportService = DatabaseImportService(
        validateDatabaseUseCase: ValidateDatabaseUseCase(),
      );

      coordinator = DatabaseSessionCoordinator(
        localDataSource: localDataSource,
        databaseRegistryRepository: registryRepository,
        databaseSecurityRepository: securityRepository,
        getActiveDatabaseUseCase: GetActiveDatabaseUseCase(registryRepository),
        secureDataSource: secureDataSource,
        databaseImportService: databaseImportService,
        resolveDatabaseDuplicateUseCase: ResolveDatabaseDuplicateUseCase(
          registryRepository,
        ),
        databaseSyncRepository: syncRepository,
        unlockDatabaseUseCase: UnlockDatabaseUseCase(),
        appleAutofillV2Coordinator: appleAutofillV2Coordinator,
      );
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test(
      'checkInitialDatabase opens active database when many exist',
      () async {
        final pathA = await _writeManagedDatabase(tempDir, 'a.kdbx');
        final pathB = await _writeManagedDatabase(tempDir, 'b.kdbx');
        registryRepository.records = [
          _record(id: 'db-a', path: pathA),
          _record(id: 'db-b', path: pathB, lastOpenedAt: DateTime(2026, 2)),
        ];
        registryRepository.activeId = 'db-b';

        final result = await coordinator.checkInitialDatabase();

        expect(result.status, DatabaseSessionStatus.success);
        expect(result.path, pathB);
        expect(localDataSource.selectedDatabasePath, pathB);
        expect(registryRepository.activeId, 'db-b');
        expect(registryRepository.records, hasLength(2));
      },
    );

    test(
      'checkInitialDatabase falls back when active database is gone',
      () async {
        final pathA = await _writeManagedDatabase(tempDir, 'a.kdbx');
        final pathB = await _writeManagedDatabase(tempDir, 'b.kdbx');
        registryRepository.records = [
          _record(id: 'db-a', path: pathA),
          _record(id: 'db-b', path: '${tempDir.path}/missing.kdbx'),
        ];
        registryRepository.activeId = 'db-b';

        final result = await coordinator.checkInitialDatabase();

        expect(result.status, DatabaseSessionStatus.unselected);
        expect(result.recentDatabasePaths, containsAll([pathA, pathB]));
        expect(localDataSource.selectedDatabasePath, isNull);
        expect(registryRepository.activeId, 'db-b');
      },
    );

    test(
      'checkInitialDatabase uses only remaining database when active path is stale',
      () async {
        final pathA = await _writeManagedDatabase(tempDir, 'a.kdbx');
        final stalePathB = '${tempDir.path}/databases/b.kdbx';
        registryRepository.records = [
          _record(id: 'db-a', path: pathA),
          _record(id: 'db-b', path: stalePathB),
        ];
        registryRepository.activeId = 'db-b';
        localDataSource.selectedKeyFilePath = '/tmp/stale.key';
        secureDataSource.password = 'stale-secret';

        final result = await coordinator.checkInitialDatabase();

        expect(result.status, DatabaseSessionStatus.success);
        expect(result.path, pathA);
        expect(result.path, isNot(stalePathB));
        expect(localDataSource.selectedDatabasePath, pathA);
        expect(localDataSource.selectedKeyFilePath, isNull);
        expect(secureDataSource.password, isNull);
        expect(appleAutofillV2Coordinator.clearCallCount, 1);
      },
    );

    test(
      'openRecentDatabase failure does not update active database',
      () async {
        registryRepository.activeId = 'db-old';

        await expectLater(
          coordinator.openRecentDatabase('${tempDir.path}/missing.kdbx'),
          throwsException,
        );

        expect(registryRepository.activeId, 'db-old');
        expect(localDataSource.selectedDatabasePath, isNull);
      },
    );

    test('checkInitialDatabase does not duplicate the only record', () async {
      final path = await _writeManagedDatabase(tempDir, 'only.kdbx');
      registryRepository.records = [_record(id: 'db-only', path: path)];
      registryRepository.activeId = 'db-only';

      final result = await coordinator.checkInitialDatabase();

      expect(result.status, DatabaseSessionStatus.success);
      expect(result.path, path);
      expect(registryRepository.records, hasLength(1));
      expect(registryRepository.records.single.databaseId, 'db-only');
    });

    test('invalid overwrite keeps existing database bytes', () async {
      final targetPath = await _writeManagedDatabase(tempDir, 'existing.kdbx');
      final originalBytes = await File(targetPath).readAsBytes();
      final invalidFile = File('${tempDir.path}/incoming/existing.kdbx');
      await invalidFile.parent.create(recursive: true);
      await invalidFile.writeAsBytes(const [1, 2, 3], flush: true);

      await expectLater(
        databaseImportService.importFromSelection(
          fileName: 'existing.kdbx',
          selectedPath: invalidFile.path,
          overwriteExisting: true,
        ),
        throwsException,
      );

      expect(await File(targetPath).readAsBytes(), originalBytes);
      expect(
        await Directory(
          '${tempDir.path}/databases',
        ).list().where((entry) => entry is File).length,
        1,
      );
    });

    test('local duplicate cancel preserves existing database bytes', () async {
      final targetPath = await _writeManagedDatabase(tempDir, 'existing.kdbx');
      final originalBytes = await File(targetPath).readAsBytes();
      final incomingBytes = <int>[
        0x03,
        0xD9,
        0xA2,
        0x9A,
        0x67,
        0xFB,
        0x4B,
        0xB5,
        ...utf8.encode('incoming'),
      ];
      final incomingFile = File('${tempDir.path}/incoming/existing.kdbx');
      await incomingFile.parent.create(recursive: true);
      await incomingFile.writeAsBytes(incomingBytes, flush: true);
      registryRepository.records = [
        _record(
          id: 'db-existing',
          path: targetPath,
        ).copyWith(fileHash: md5.convert(incomingBytes).toString()),
      ];

      final pending = await coordinator.selectExistingDatabase(
        fileName: 'existing.kdbx',
        selectedPath: incomingFile.path,
        overwriteExisting: true,
      );
      expect(pending.status, DatabaseSessionStatus.duplicateDecisionRequired);
      expect(await File(targetPath).readAsBytes(), originalBytes);

      final resolved = await coordinator.resolveDuplicateDecision(
        duplicatePrompt: pending.duplicatePrompt!,
        decision: DatabaseDuplicateResolution.cancel,
      );

      expect(resolved.status, DatabaseSessionStatus.unselected);
      expect(await File(targetPath).readAsBytes(), originalBytes);
      final staging = Directory('${tempDir.path}/database_imports');
      expect(await staging.list().isEmpty, isTrue);
    });

    test('local overwrite commits only after validation and dedup', () async {
      final targetPath = await _writeManagedDatabase(tempDir, 'existing.kdbx');
      final originalBytes = await File(targetPath).readAsBytes();
      final incomingBytes = <int>[
        0x03,
        0xD9,
        0xA2,
        0x9A,
        0x67,
        0xFB,
        0x4B,
        0xB5,
        ...utf8.encode('replacement'),
      ];
      final incomingFile = File('${tempDir.path}/incoming/existing.kdbx');
      await incomingFile.parent.create(recursive: true);
      await incomingFile.writeAsBytes(incomingBytes, flush: true);
      registryRepository.records = [
        _record(
          id: 'db-existing',
          path: targetPath,
        ).copyWith(fileHash: md5.convert(originalBytes).toString()),
      ];

      final result = await coordinator.selectExistingDatabase(
        fileName: 'existing.kdbx',
        selectedPath: incomingFile.path,
        overwriteExisting: true,
      );

      expect(result.status, DatabaseSessionStatus.success);
      expect(result.path, targetPath);
      expect(await File(targetPath).readAsBytes(), incomingBytes);
      expect(registryRepository.records.single.databaseId, 'db-existing');
      final staging = Directory('${tempDir.path}/database_imports');
      expect(await staging.list().isEmpty, isTrue);
    });

    test('corrupt Drive overwrite preserves existing bytes', () async {
      final existingPath = await _writeManagedDatabase(tempDir, 'remote.kdbx');
      final originalBytes = await File(existingPath).readAsBytes();
      syncRepository.downloadBytes = Uint8List.fromList(const [1, 2, 3]);

      await expectLater(
        coordinator.selectDriveDatabase(
          remoteFileId: 'remote-id',
          remoteFileName: 'remote.kdbx',
          overwriteExisting: true,
        ),
        throwsException,
      );

      expect(await File(existingPath).readAsBytes(), originalBytes);
      final staging = Directory('${tempDir.path}/database_imports');
      expect(
        await staging.exists() ? await staging.list().isEmpty : true,
        isTrue,
      );
    });

    test('Drive listing connects before loading remote files', () async {
      syncRepository.remoteFiles = const [
        DriveRemoteFile(id: 'remote-id', name: 'remote.kdbx'),
      ];

      final files = await coordinator.listDriveDatabases();

      expect(syncRepository.connectCalls, 1);
      expect(files.single.name, 'remote.kdbx');
    });

    test('Drive duplicate cancel preserves file and mapping', () async {
      final existingPath = await _prepareDriveDuplicate(
        tempDir,
        registryRepository,
        syncRepository,
      );
      final originalBytes = await File(existingPath).readAsBytes();

      final pending = await coordinator.selectDriveDatabase(
        remoteFileId: 'remote-id',
        remoteFileName: 'remote.kdbx',
        overwriteExisting: true,
      );

      expect(await File(existingPath).readAsBytes(), originalBytes);
      final resolved = await coordinator.resolveDuplicateDecision(
        duplicatePrompt: pending.duplicatePrompt!,
        decision: DatabaseDuplicateResolution.cancel,
      );

      expect(resolved.status, DatabaseSessionStatus.unselected);
      expect(await File(existingPath).readAsBytes(), originalBytes);
      expect(syncRepository.mappings[existingPath]!.driveFileId, 'old-remote');
      expect(registryRepository.records, hasLength(1));
    });

    test('Drive duplicate useExisting discards staged file', () async {
      final existingPath = await _prepareDriveDuplicate(
        tempDir,
        registryRepository,
        syncRepository,
      );
      final originalBytes = await File(existingPath).readAsBytes();

      final pending = await coordinator.selectDriveDatabase(
        remoteFileId: 'remote-id',
        remoteFileName: 'remote.kdbx',
        overwriteExisting: true,
      );
      final resolved = await coordinator.resolveDuplicateDecision(
        duplicatePrompt: pending.duplicatePrompt!,
        decision: DatabaseDuplicateResolution.useExisting,
      );

      expect(resolved.path, existingPath);
      expect(await File(existingPath).readAsBytes(), originalBytes);
      expect(syncRepository.mappings[existingPath]!.driveFileId, 'remote-id');
      expect(registryRepository.records, hasLength(1));
    });

    test('Drive duplicate keepBoth preserves existing mapping', () async {
      final existingPath = await _prepareDriveDuplicate(
        tempDir,
        registryRepository,
        syncRepository,
      );

      final pending = await coordinator.selectDriveDatabase(
        remoteFileId: 'remote-id',
        remoteFileName: 'remote.kdbx',
        overwriteExisting: true,
      );
      final resolved = await coordinator.resolveDuplicateDecision(
        duplicatePrompt: pending.duplicatePrompt!,
        decision: DatabaseDuplicateResolution.keepBoth,
      );

      expect(resolved.path, isNot(existingPath));
      expect(await File(resolved.path!).exists(), isTrue);
      expect(registryRepository.records, hasLength(2));
      expect(syncRepository.mappings[existingPath]!.driveFileId, 'old-remote');
      expect(syncRepository.mappings[resolved.path]!.driveFileId, 'remote-id');
    });

    test(
      'Drive duplicate replace swaps file and mapping after decision',
      () async {
        final existingPath = await _prepareDriveDuplicate(
          tempDir,
          registryRepository,
          syncRepository,
        );
        final originalBytes = await File(existingPath).readAsBytes();

        final pending = await coordinator.selectDriveDatabase(
          remoteFileId: 'remote-id',
          remoteFileName: 'remote.kdbx',
          overwriteExisting: true,
        );
        expect(await File(existingPath).readAsBytes(), originalBytes);

        final resolved = await coordinator.resolveDuplicateDecision(
          duplicatePrompt: pending.duplicatePrompt!,
          decision: DatabaseDuplicateResolution.replaceExisting,
        );

        expect(resolved.path, existingPath);
        expect(
          await File(existingPath).readAsBytes(),
          syncRepository.downloadBytes,
        );
        expect(syncRepository.mappings[existingPath]!.driveFileId, 'remote-id');
        expect(registryRepository.records, hasLength(1));
        expect(registryRepository.records.single.canonicalPath, existingPath);
      },
    );

    test('protected key paths include shared profiles once', () async {
      const sharedPath = '/tmp/shared.key';
      registryRepository.records = [
        _record(id: 'db-a', path: '/tmp/a.kdbx'),
        _record(id: 'db-b', path: '/tmp/b.kdbx'),
      ];
      securityRepository.profiles['db-a'] = const DatabaseSecurityProfile(
        databaseId: 'db-a',
        keyFilePath: sharedPath,
      );
      securityRepository.profiles['db-b'] = const DatabaseSecurityProfile(
        databaseId: 'db-b',
        keyFilePath: sharedPath,
      );

      expect(await coordinator.getProtectedKeyFilePaths(), {sharedPath});
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
        localDataSource.selectedKeyFilePath = '/tmp/key.key';

        final result = await coordinator.openRecentDatabase(currentPath);

        expect(result.status, DatabaseSessionStatus.success);
        expect(result.path, currentPath);
        expect(result.duplicatePrompt, isNull);
        expect(registryRepository.activeId, 'db-current');
        expect(localDataSource.selectedDatabasePath, currentPath);
        expect(localDataSource.selectedKeyFilePath, isNull);
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
      securityRepository.profiles['db-current'] = const DatabaseSecurityProfile(
        databaseId: 'db-current',
        keyFilePath: '/tmp/key.key',
      );
      localDataSource.selectedDatabasePath = currentPath;
      localDataSource.selectedKeyFilePath = '/tmp/key.key';
      secureDataSource.password = 'secret';

      final result = await coordinator.removeRecentDatabase(
        path: currentPath,
        mode: RecentDatabaseRemovalMode.removeOnly,
      );

      expect(result.status, DatabaseSessionStatus.info);
      expect(registryRepository.records, isEmpty);
      expect(securityRepository.profiles, isEmpty);
      expect(localDataSource.selectedDatabasePath, '');
      expect(localDataSource.selectedKeyFilePath, isNull);
      expect(secureDataSource.password, isNull);
      expect(appleAutofillV2Coordinator.clearCallCount, 1);
    });

    test(
      'initializeUnlock clears stale cached key file for registered database without profile key',
      () async {
        final databasePath = await _writeManagedDatabase(tempDir, 'plain.kdbx');
        final staleKeyPath = '${tempDir.path}/keys/other.key';
        await File(staleKeyPath).create(recursive: true);
        registryRepository.records = [
          _record(id: 'db-plain', path: databasePath),
        ];
        localDataSource.selectedKeyFilePath = staleKeyPath;

        final result = await coordinator.initializeUnlock(
          databasePath: databasePath,
          biometricAvailable: false,
        );

        expect(result.keyFilePath, isNull);
        expect(localDataSource.selectedKeyFilePath, isNull);
      },
    );

    test(
      'initializeUnlock syncs profile key file into selected key cache',
      () async {
        final databasePath = await _writeManagedDatabase(tempDir, 'keyed.kdbx');
        final keyPath = '${tempDir.path}/keys/database.key';
        await File(keyPath).create(recursive: true);
        registryRepository.records = [
          _record(id: 'db-keyed', path: databasePath),
        ];
        securityRepository.profiles['db-keyed'] = DatabaseSecurityProfile(
          databaseId: 'db-keyed',
          keyFilePath: keyPath,
          biometricProtectionEnabled: false,
        );

        final result = await coordinator.initializeUnlock(
          databasePath: databasePath,
          biometricAvailable: false,
        );

        expect(result.keyFilePath, keyPath);
        expect(localDataSource.selectedKeyFilePath, keyPath);
      },
    );

    test(
      'initializeUnlock keeps cached key fallback for unregistered database',
      () async {
        final keyPath = '${tempDir.path}/keys/legacy.key';
        await File(keyPath).create(recursive: true);
        localDataSource.selectedKeyFilePath = keyPath;

        final result = await coordinator.initializeUnlock(
          databasePath: '${tempDir.path}/legacy.kdbx',
          biometricAvailable: false,
        );

        expect(result.keyFilePath, keyPath);
        expect(localDataSource.selectedKeyFilePath, keyPath);
      },
    );
  });
}

Future<String> _prepareDriveDuplicate(
  Directory root,
  _FakeRegistryRepository registryRepository,
  _FakeSyncRepository syncRepository,
) async {
  final existingPath = await _writeManagedDatabase(root, 'existing.kdbx');
  registryRepository.records = [
    DatabaseRecord(
      databaseId: 'db-existing',
      canonicalPath: existingPath,
      displayName: 'existing.kdbx',
      sourceType: DatabaseSourceType.drive,
      sourceRef: 'remote-id',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ];
  syncRepository.downloadBytes = Uint8List.fromList([
    0x03,
    0xD9,
    0xA2,
    0x9A,
    0x67,
    0xFB,
    0x4B,
    0xB5,
    ...utf8.encode('downloaded'),
  ]);
  syncRepository.mappings[existingPath] = DatabaseSyncMapping(
    databasePath: existingPath,
    driveFileId: 'old-remote',
    driveFileName: 'old.kdbx',
    lastSyncAt: null,
    autoSyncEnabled: true,
  );
  return existingPath;
}

Future<String> _writeManagedDatabase(Directory root, String fileName) async {
  final directory = Directory('${root.path}/databases');
  await directory.create(recursive: true);
  final path = '${directory.path}/$fileName';
  await File(path).writeAsBytes(<int>[
    0x03,
    0xD9,
    0xA2,
    0x9A,
    0x67,
    0xFB,
    0x4B,
    0xB5,
    ...utf8.encode(fileName),
  ], flush: true);
  return path;
}

DatabaseRecord _record({
  required String id,
  required String path,
  DateTime? lastOpenedAt,
}) {
  return DatabaseRecord(
    databaseId: id,
    canonicalPath: path,
    displayName: path.split('/').last,
    sourceType: DatabaseSourceType.local,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    lastOpenedAt: lastOpenedAt,
  );
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.basePath);

  final String basePath;

  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;
}

class _FakeLocalDataSource implements LocalDataSource {
  String? selectedDatabasePath;
  String? selectedKeyFilePath;
  bool autofillPromptSeen = false;

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
  Future<bool> getAutofillPromptSeen() async => autofillPromptSeen;

  @override
  Future<void> setAutofillPromptSeen(bool seen) async {
    autofillPromptSeen = seen;
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
  Uint8List downloadBytes = Uint8List(0);
  final Map<String, DatabaseSyncMapping> mappings = {};
  List<DriveRemoteFile> remoteFiles = const [];
  bool connected = false;
  int connectCalls = 0;

  @override
  Future<void> connect() async {
    connectCalls += 1;
    connected = true;
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<Uint8List> downloadRemoteFile(String fileId) async {
    return downloadBytes;
  }

  @override
  Future<DatabaseSyncMapping?> getMapping(String databasePath) async {
    return mappings[databasePath];
  }

  @override
  Future<bool> isConnected() async => connected;

  @override
  Future<DatabaseSyncMapping> linkDatabaseToDrive({
    required String databasePath,
    String? remoteFileId,
    String? remoteFileName,
  }) async {
    final mapping = DatabaseSyncMapping(
      databasePath: databasePath,
      driveFileId: remoteFileId ?? 'remote-id',
      driveFileName: remoteFileName ?? 'remote.kdbx',
      lastSyncAt: null,
      autoSyncEnabled: true,
    );
    mappings[databasePath] = mapping;
    return mapping;
  }

  @override
  Future<List<DriveRemoteFile>> listRemoteFiles({String? query}) async {
    return remoteFiles;
  }

  @override
  Future<void> moveMappingPath({
    required String fromDatabasePath,
    required String toDatabasePath,
  }) async {
    final mapping = mappings.remove(fromDatabasePath);
    if (mapping != null) {
      mappings[toDatabasePath] = mapping.copyWith(databasePath: toDatabasePath);
    }
  }

  @override
  Future<void> removeMapping(String databasePath) async {
    mappings.remove(databasePath);
  }

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
