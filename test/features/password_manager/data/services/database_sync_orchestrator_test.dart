import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/sync_metadata_data_source.dart';
import 'package:password_manager/features/password_manager/data/services/database_sync_orchestrator.dart';
import 'package:password_manager/features/password_manager/data/services/google_drive_api_service.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_mapping.dart';
import 'package:password_manager/features/password_manager/domain/models/drive_remote_file.dart';
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
