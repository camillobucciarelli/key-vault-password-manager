import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kdbx/kdbx.dart';
import 'package:password_manager/features/password_manager/data/datasources/sync_metadata_data_source.dart';
import 'package:password_manager/features/password_manager/data/services/database_path_mutex.dart';
import 'package:password_manager/features/password_manager/data/services/database_sync_orchestrator.dart';
import 'package:password_manager/features/password_manager/data/services/google_drive_api_service.dart';
import 'package:password_manager/features/password_manager/data/services/vault_kdbx_service.dart';
import 'package:password_manager/features/password_manager/domain/models/database_sync_mapping.dart';
import 'package:password_manager/features/password_manager/domain/models/drive_remote_file.dart';
import 'package:password_manager/features/password_manager/domain/repositories/database_sync_repository.dart';
import 'package:path/path.dart' as p;

// =============================================================================
// spec 008 Gate 1 — lost-update proof (QA proposal, Slice C validation).
//
// A vault edit (open -> modify -> save) racing a syncNow that replaces the
// local file must serialize on the SHARED DatabasePathMutex. Without
// serialization the edit reads the pre-sync bytes and its save is clobbered by
// (or clobbers) the sync replacement — a silent lost update.
//
// The download is gated on a Completer so the interleaving is deterministic:
// sync acquires the lock and parks on the network; the edit is dispatched
// while sync is parked; the gate opens; both settle. With the real mutex the
// edit waits and lands ON TOP of the downloaded remote bytes. Any bypass of
// the lock in either writer makes the final file lose one of the two writes.
// =============================================================================

const _password = 'test-password';

void main() {
  test(
    'a vault edit racing syncNow serializes and neither write is lost',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('edit_vs_sync_');
      addTearDown(() => tempDir.delete(recursive: true));
      final databasePath = p.join(tempDir.path, 'vault.kdbx');

      final credentials = Credentials(ProtectedValue.fromString(_password));
      final localKdbx = KdbxFormat().create(credentials, 'Local');
      final localBytes = await localKdbx.save();
      await File(databasePath).writeAsBytes(localBytes, flush: true);

      // Remote: a DIFFERENT valid vault with the same password, containing a
      // marker entry so the replacement is observable.
      final remoteKdbx = KdbxFormat().create(
        Credentials(ProtectedValue.fromString(_password)),
        'Remote',
      );
      final remoteEntry = KdbxEntry.create(
        remoteKdbx,
        remoteKdbx.body.rootGroup,
      );
      remoteEntry.setString(KdbxKeyCommon.TITLE, PlainValue('remote-entry'));
      remoteKdbx.body.rootGroup.addEntry(remoteEntry);
      final remoteBytes = await remoteKdbx.save();

      final mutex = DatabasePathMutex();
      final vaultService = VaultKdbxService(mutex: mutex);
      final metadata = _InMemoryMetadata();
      final drive = _GatedDrive()
        ..metadataResult = DriveRemoteFile(
          id: 'remote-1',
          name: 'vault.kdbx',
          md5Checksum: md5.convert(remoteBytes).toString(),
        )
        ..downloadResult = Uint8List.fromList(remoteBytes);
      await metadata.upsertMapping(
        databasePath,
        DatabaseSyncMapping(
          databasePath: databasePath,
          driveFileId: 'remote-1',
          driveFileName: 'vault.kdbx',
          // Local unchanged, remote changed -> download+replace branch.
          lastSyncedLocalChecksum: md5.convert(localBytes).toString(),
          lastSyncedRemoteChecksum: 'stale-remote-checksum',
          lastSyncedRemoteModifiedTime: null,
          lastSyncAt: DateTime(2026),
        ),
      );
      final orchestrator = DatabaseSyncOrchestrator(
        resolveDatabaseId: (databasePath) async => databasePath,
        syncMetadataDataSource: metadata,
        googleDriveApiService: drive,
        mutex: mutex,
      );

      // 1. Sync takes the lock and parks on the gated download.
      final syncFuture = orchestrator.syncNow(databasePath);
      await drive.downloadRequested.future;

      // 2. Edit dispatched while sync holds the lock.
      // Target the remote root group: after serialization the edit reopens the
      // REPLACED file, so a pre-sync group id would fail loudly ("Group not
      // found" — correct, no silent loss; pinned implicitly here).
      final editFuture = vaultService.createEntry(
        databasePath: databasePath,
        password: _password,
        groupId: remoteKdbx.body.rootGroup.uuid.uuid,
        title: 'edited-entry',
        username: 'user',
        entryPassword: 'secret',
        url: '',
        notes: '',
      );
      // Give the edit every chance to (incorrectly) run before the download
      // completes: if it is not serialized behind the lock it writes NOW.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 3. Open the gate; both operations settle.
      drive.downloadGate.complete();
      final syncResult = await syncFuture.timeout(const Duration(seconds: 10));
      await editFuture.timeout(const Duration(seconds: 10));
      expect(syncResult, isA<SyncNowSuccess>());

      // 4. Neither write lost: the final file is the REMOTE vault (sync won the
      // lock first) with the edited entry applied on top.
      final finalKdbx = await KdbxFormat().read(
        await File(databasePath).readAsBytes(),
        Credentials(ProtectedValue.fromString(_password)),
      );
      final titles = finalKdbx.body.rootGroup
          .getAllEntries()
          .map((e) => e.getString(KdbxKeyCommon.TITLE)?.getText())
          .toList();
      expect(
        titles,
        contains('remote-entry'),
        reason: 'the sync replacement was clobbered by the racing edit',
      );
      expect(
        titles,
        contains('edited-entry'),
        reason: 'the vault edit was clobbered by the sync replacement',
      );
    },
  );
}

class _InMemoryMetadata implements SyncMetadataDataSource {
  final Map<String, DatabaseSyncMapping> _mappings = {};

  @override
  Future<DatabaseSyncMapping?> getMapping(String databasePath) async =>
      _mappings[databasePath];

  @override
  Future<void> upsertMapping(
    String databaseId,
    DatabaseSyncMapping mapping,
  ) async {
    _mappings[databaseId] = mapping.copyWith(databaseId: databaseId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not needed here');
}

class _GatedDrive implements GoogleDriveApiService {
  DriveRemoteFile? metadataResult;
  Uint8List? downloadResult;
  final Completer<void> downloadGate = Completer<void>();
  final Completer<void> downloadRequested = Completer<void>();

  @override
  Future<DriveRemoteFile> getFileMetadata(String fileId) async =>
      metadataResult!;

  @override
  Future<Uint8List> downloadFile(String fileId) async {
    if (!downloadRequested.isCompleted) {
      downloadRequested.complete();
    }
    await downloadGate.future;
    return downloadResult!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not needed here');
}
