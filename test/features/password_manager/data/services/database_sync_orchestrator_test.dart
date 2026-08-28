import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/sync_metadata_data_source.dart';
import 'package:password_manager/features/password_manager/data/services/database_file_hash_recorder.dart';
import 'package:password_manager/features/password_manager/data/services/database_sync_orchestrator.dart';
import 'package:password_manager/features/password_manager/data/services/google_drive_api_service.dart';
import 'package:password_manager/features/password_manager/data/services/safe_vault_file_writer.dart';
import 'package:password_manager/features/password_manager/domain/entities/database_record.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_mapping.dart';
import 'package:password_manager/features/password_manager/domain/models/drive_remote_file.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_registry_repository.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_sync_repository.dart';

void main() {
  late _InMemorySyncMetadataDataSource metadata;
  late _FakeGoogleDriveApiService driveApi;
  late DatabaseSyncOrchestrator orchestrator;

  setUp(() {
    metadata = _InMemorySyncMetadataDataSource();
    driveApi = _FakeGoogleDriveApiService();
    orchestrator = DatabaseSyncOrchestrator(
      syncMetadataDataSource: metadata,
      googleDriveApiService: driveApi,
    );
  });

  test(
    'first sync without baseline succeeds when local and remote match',
    () async {
      final localBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final localFile = await _createTempDatabase(localBytes);
      addTearDown(() => localFile.parent.delete(recursive: true));

      const remoteFileId = 'remote-file-1';
      final checksum = md5.convert(localBytes).toString();

      await metadata.upsertMapping(
        DatabaseSyncMapping(
          databasePath: localFile.path,
          driveFileId: remoteFileId,
          driveFileName: 'vault.kdbx',
          lastSyncedLocalChecksum: null,
          lastSyncedRemoteChecksum: null,
          lastSyncedRemoteModifiedTime: null,
          lastSyncAt: null,
        ),
      );

      driveApi.setFile(
        id: remoteFileId,
        name: 'vault.kdbx',
        bytes: localBytes,
        md5Checksum: checksum,
      );

      final result = await orchestrator.syncNow(localFile.path);

      expect(result, isA<SyncNowSuccess>());
      final updated = await metadata.getMapping(localFile.path);
      expect(updated, isNotNull);
      expect(updated!.lastSyncedLocalChecksum, checksum);
      expect(updated.lastSyncedRemoteChecksum, checksum);
      expect(updated.lastSyncAt, isNotNull);
    },
  );

  test(
    'first sync without baseline returns conflict when checksums differ',
    () async {
      final localBytes = Uint8List.fromList([1, 2, 3]);
      final remoteBytes = Uint8List.fromList([9, 8, 7]);
      final localFile = await _createTempDatabase(localBytes);
      addTearDown(() => localFile.parent.delete(recursive: true));

      const remoteFileId = 'remote-file-2';

      await metadata.upsertMapping(
        DatabaseSyncMapping(
          databasePath: localFile.path,
          driveFileId: remoteFileId,
          driveFileName: 'vault.kdbx',
        ),
      );

      driveApi.setFile(
        id: remoteFileId,
        name: 'vault.kdbx',
        bytes: remoteBytes,
        md5Checksum: md5.convert(remoteBytes).toString(),
      );

      final result = await orchestrator.syncNow(localFile.path);

      expect(result, isA<SyncNowConflict>());
      final conflict = (result as SyncNowConflict).conflict;
      expect(conflict.firstSyncWithoutBaseline, isTrue);
      expect(conflict.localChanged, isTrue);
      expect(conflict.remoteChanged, isTrue);
      expect(conflict.localChecksum, md5.convert(localBytes).toString());
      expect(conflict.remoteChecksum, md5.convert(remoteBytes).toString());
    },
  );

  test('remote checksum fallback via download avoids false conflict', () async {
    final localBytes = Uint8List.fromList([11, 12, 13, 14]);
    final localFile = await _createTempDatabase(localBytes);
    addTearDown(() => localFile.parent.delete(recursive: true));

    const remoteFileId = 'remote-file-3';
    final checksum = md5.convert(localBytes).toString();

    await metadata.upsertMapping(
      DatabaseSyncMapping(
        databasePath: localFile.path,
        driveFileId: remoteFileId,
        driveFileName: 'vault.kdbx',
      ),
    );

    driveApi.setFile(
      id: remoteFileId,
      name: 'vault.kdbx',
      bytes: localBytes,
      md5Checksum: null,
    );

    final result = await orchestrator.syncNow(localFile.path);

    expect(result, isA<SyncNowSuccess>());
    final updated = await metadata.getMapping(localFile.path);
    expect(updated, isNotNull);
    expect(updated!.lastSyncedLocalChecksum, checksum);
    expect(updated.lastSyncedRemoteChecksum, checksum);
  });

  test('a Drive-linked mapping moves exactly, restorable on failure', () async {
    final destination = DatabaseSyncMapping(
      databasePath: '/tmp/dest.kdbx',
      driveFileId: 'destination-remote-id',
      driveFileName: 'destination.kdbx',
    );
    final source = DatabaseSyncMapping(
      databasePath: '/tmp/source.kdbx',
      driveFileId: 'source-remote-id',
      driveFileName: 'source.kdbx',
    );
    await metadata.upsertMapping(source);
    await metadata.upsertMapping(destination);

    final move = await metadata.moveMappingPath(
      fromDatabasePath: source.databasePath,
      toDatabasePath: destination.databasePath,
    );

    // Forward move replaced the destination with the (renamed) source and
    // left no trace at the old source path.
    expect(await metadata.getMapping(source.databasePath), isNull);
    expect(
      (await metadata.getMapping(destination.databasePath))?.driveFileId,
      'source-remote-id',
    );

    await metadata.restoreMappingPathMove(move);

    // Restore is byte-for-byte, not a blind reverse move: the destination's
    // ORIGINAL mapping is back, not the moved source.
    expect(
      (await metadata.getMapping(source.databasePath))?.driveFileId,
      'source-remote-id',
    );
    expect(
      (await metadata.getMapping(destination.databasePath))?.driveFileId,
      'destination-remote-id',
    );
  });

  test('sync invalidation failure blocks remote replacement', () async {
    final harness = await _createHashSyncHarness(failUpsertOnCall: 1);
    addTearDown(() => harness.localFile.parent.delete(recursive: true));

    await expectLater(
      harness.orchestrator.syncNow(harness.localFile.path),
      throwsStateError,
    );

    expect(await harness.localFile.readAsBytes(), harness.localBytes);
    expect(harness.registry.record.fileHash, harness.localHash);
  });

  test('sync writer failure restores the previous hash', () async {
    final harness = await _createHashSyncHarness(
      safeWriter: _FailingSafeVaultFileWriter(),
    );
    addTearDown(() => harness.localFile.parent.delete(recursive: true));

    await expectLater(
      harness.orchestrator.syncNow(harness.localFile.path),
      throwsException,
    );

    expect(await harness.localFile.readAsBytes(), harness.localBytes);
    expect(harness.registry.record.fileHash, harness.localHash);
  });

  test('sync hash refresh failure leaves the hash absent, not stale', () async {
    final harness = await _createHashSyncHarness(failUpsertOnCall: 2);
    addTearDown(() => harness.localFile.parent.delete(recursive: true));

    final result = await harness.orchestrator.syncNow(harness.localFile.path);

    expect(result, isA<SyncNowSuccess>());
    expect(await harness.localFile.readAsBytes(), harness.remoteBytes);
    expect(harness.registry.record.fileHash, isNull);
  });

  test('remote replacement refreshes the registry file hash', () async {
    final harness = await _createHashSyncHarness();
    addTearDown(() => harness.localFile.parent.delete(recursive: true));

    final result = await harness.orchestrator.syncNow(harness.localFile.path);

    expect(result, isA<SyncNowSuccess>());
    expect(harness.registry.record.fileHash, harness.remoteHash);
    expect(await harness.localFile.readAsBytes(), harness.remoteBytes);
  });
}

class _HashSyncHarness {
  const _HashSyncHarness({
    required this.localFile,
    required this.localBytes,
    required this.remoteBytes,
    required this.localHash,
    required this.remoteHash,
    required this.registry,
    required this.orchestrator,
  });

  final File localFile;
  final Uint8List localBytes;
  final Uint8List remoteBytes;
  final String localHash;
  final String remoteHash;
  final _FakeRegistryRepository registry;
  final DatabaseSyncOrchestrator orchestrator;
}

Future<_HashSyncHarness> _createHashSyncHarness({
  int? failUpsertOnCall,
  SafeVaultFileWriter? safeWriter,
}) async {
  final localBytes = Uint8List.fromList([1, 2, 3]);
  final remoteBytes = Uint8List.fromList([9, 8, 7]);
  final localFile = await _createTempDatabase(localBytes);
  final localHash = md5.convert(localBytes).toString();
  final remoteHash = md5.convert(remoteBytes).toString();
  const remoteFileId = 'remote-file-hash-refresh';
  final registry = _FakeRegistryRepository(
    DatabaseRecord(
      databaseId: 'db-1',
      canonicalPath: localFile.path,
      displayName: 'vault.kdbx',
      sourceType: DatabaseSourceType.drive,
      fileHash: localHash,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
  )..failUpsertOnCall = failUpsertOnCall;
  final localMetadata = _InMemorySyncMetadataDataSource();
  final driveService = _FakeGoogleDriveApiService();
  await localMetadata.upsertMapping(
    DatabaseSyncMapping(
      databasePath: localFile.path,
      driveFileId: remoteFileId,
      driveFileName: 'vault.kdbx',
      lastSyncedLocalChecksum: localHash,
      lastSyncedRemoteChecksum: localHash,
    ),
  );
  driveService.setFile(
    id: remoteFileId,
    name: 'vault.kdbx',
    bytes: remoteBytes,
    md5Checksum: remoteHash,
  );
  return _HashSyncHarness(
    localFile: localFile,
    localBytes: localBytes,
    remoteBytes: remoteBytes,
    localHash: localHash,
    remoteHash: remoteHash,
    registry: registry,
    orchestrator: DatabaseSyncOrchestrator(
      syncMetadataDataSource: localMetadata,
      googleDriveApiService: driveService,
      safeWriter: safeWriter,
      fileHashRecorder: DatabaseFileHashRecorder(registryRepository: registry),
    ),
  );
}

class _FakeRegistryRepository implements DatabaseRegistryRepository {
  _FakeRegistryRepository(this.record);

  DatabaseRecord record;
  int? failUpsertOnCall;
  int upsertCalls = 0;

  @override
  Future<DatabaseRecord?> findByHash(String fileHash) async => null;

  @override
  Future<DatabaseRecord?> findBySource({
    required DatabaseSourceType sourceType,
    required String sourceRef,
  }) async => null;

  @override
  Future<String?> getActive() async => record.databaseId;

  @override
  Future<DatabaseRecord?> getById(String databaseId) async => record;

  @override
  Future<List<DatabaseRecord>> list() async => [record];

  @override
  Future<void> remove(String databaseId) async {}

  @override
  Future<void> setActive(String? databaseId) async {}

  @override
  Future<void> upsert(DatabaseRecord value) async {
    upsertCalls += 1;
    if (failUpsertOnCall == upsertCalls) {
      throw StateError('registry write failed');
    }
    record = value;
  }
}

class _FailingSafeVaultFileWriter extends SafeVaultFileWriter {
  @override
  Future<SafeVaultFileWriteResult> write({
    required String targetPath,
    required Uint8List bytes,
    bool backupExistingTarget = false,
    String? operation,
  }) async {
    throw Exception('writer unavailable');
  }
}

Future<File> _createTempDatabase(Uint8List bytes) async {
  final dir = await Directory.systemTemp.createTemp(
    'db_sync_orchestrator_test_',
  );
  final file = File('${dir.path}/vault.kdbx');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

class _InMemorySyncMetadataDataSource implements SyncMetadataDataSource {
  final Map<String, DatabaseSyncMapping> _mappings = {};
  final Map<String, PendingMergeUpload> _pendingUploads = {};

  @override
  Future<PendingMergeUpload?> getPendingUpload(String databasePath) async {
    return _pendingUploads[databasePath];
  }

  @override
  Future<void> upsertPendingUpload(PendingMergeUpload record) async {
    _pendingUploads[record.databasePath] = record;
  }

  @override
  Future<void> clearPendingUpload(String databasePath) async {
    _pendingUploads.remove(databasePath);
  }

  @override
  Future<List<DatabaseSyncMapping>> getAllMappings() async {
    return _mappings.values.toList(growable: false);
  }

  @override
  Future<DatabaseSyncMapping?> getMapping(String databasePath) async {
    return _mappings[databasePath];
  }

  @override
  Future<void> removeMapping(String databasePath) async {
    _mappings.remove(databasePath);
  }

  @override
  Future<DatabaseSyncMappingPathMove> moveMappingPath({
    required String fromDatabasePath,
    required String toDatabasePath,
  }) async {
    final move = DatabaseSyncMappingPathMove(
      fromDatabasePath: fromDatabasePath,
      toDatabasePath: toDatabasePath,
      sourceBefore: _mappings[fromDatabasePath],
      destinationBefore: _mappings[toDatabasePath],
    );
    if (fromDatabasePath == toDatabasePath) {
      return move;
    }
    final existing = _mappings.remove(fromDatabasePath);
    if (existing == null) {
      return move;
    }
    _mappings[toDatabasePath] = existing.copyWith(databasePath: toDatabasePath);
    return move;
  }

  @override
  Future<void> restoreMappingPathMove(DatabaseSyncMappingPathMove move) async {
    _mappings
      ..remove(move.fromDatabasePath)
      ..remove(move.toDatabasePath);
    if (move.sourceBefore != null) {
      _mappings[move.fromDatabasePath] = move.sourceBefore!;
    }
    if (move.destinationBefore != null) {
      _mappings[move.toDatabasePath] = move.destinationBefore!;
    }
  }

  @override
  Future<void> upsertMapping(DatabaseSyncMapping mapping) async {
    _mappings[mapping.databasePath] = mapping;
  }
}

class _FakeGoogleDriveApiService implements GoogleDriveApiService {
  final Map<String, _RemoteFileState> _files = {};

  void setFile({
    required String id,
    required String name,
    required Uint8List bytes,
    required String? md5Checksum,
  }) {
    _files[id] = _RemoteFileState(
      id: id,
      name: name,
      bytes: bytes,
      md5Checksum: md5Checksum,
      modifiedTime: DateTime.now(),
    );
  }

  @override
  Future<DriveRemoteFile> createFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    const id = 'created-file-id';
    setFile(
      id: id,
      name: fileName,
      bytes: bytes,
      md5Checksum: md5.convert(bytes).toString(),
    );
    return getFileMetadata(id);
  }

  @override
  Future<Uint8List> downloadFile(String fileId) async {
    final file = _files[fileId];
    if (file == null) {
      throw Exception('Missing file state for $fileId');
    }
    return file.bytes;
  }

  @override
  Future<DriveRemoteFile> getFileMetadata(String fileId) async {
    final file = _files[fileId];
    if (file == null) {
      throw Exception('Missing file state for $fileId');
    }
    return DriveRemoteFile(
      id: file.id,
      name: file.name,
      modifiedTime: file.modifiedTime,
      md5Checksum: file.md5Checksum,
    );
  }

  @override
  Future<List<DriveRemoteFile>> listKdbxFilesInDrive({String? query}) async {
    return _files.values
        .map(
          (file) => DriveRemoteFile(
            id: file.id,
            name: file.name,
            modifiedTime: file.modifiedTime,
            md5Checksum: file.md5Checksum,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<DriveRemoteFile> updateFile({
    required String fileId,
    required Uint8List bytes,
  }) async {
    final current = _files[fileId];
    if (current == null) {
      throw Exception('Missing file state for $fileId');
    }

    final next = _RemoteFileState(
      id: current.id,
      name: current.name,
      bytes: bytes,
      md5Checksum: md5.convert(bytes).toString(),
      modifiedTime: DateTime.now(),
    );
    _files[fileId] = next;
    return DriveRemoteFile(
      id: next.id,
      name: next.name,
      modifiedTime: next.modifiedTime,
      md5Checksum: next.md5Checksum,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RemoteFileState {
  const _RemoteFileState({
    required this.id,
    required this.name,
    required this.bytes,
    required this.md5Checksum,
    required this.modifiedTime,
  });

  final String id;
  final String name;
  final Uint8List bytes;
  final String? md5Checksum;
  final DateTime modifiedTime;
}
