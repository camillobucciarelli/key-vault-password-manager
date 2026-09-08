// spec 017 T302/T402 — the restore and clear sequences, with fakes: a locked
// session writes nothing; the backup precedes the clear; a failed write
// leaves the backup and reports it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/vault_kdbx_service.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/entry_history_coordinator.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/session_secret_holder.dart';

import 'fake_database_ports.dart';

class _FakeVaultKdbxService implements VaultKdbxService {
  final List<(String entryId, DateTime replacedAt)> restores = [];
  final List<String> clears = [];
  Object? restoreError;
  Object? clearError;

  /// What the clear observed on disk when it ran — the backup's existence
  /// at that instant is what "before" means.
  void Function()? onClear;

  @override
  Future<void> restoreEntryRevision({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String entryId,
    required DateTime replacedAt,
  }) async {
    if (restoreError != null) throw restoreError!;
    restores.add((entryId, replacedAt));
  }

  @override
  Future<void> clearEntryHistory({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String entryId,
  }) async {
    onClear?.call();
    if (clearError != null) throw clearError!;
    clears.add(entryId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final replacedAt = DateTime.utc(2026, 3, 1, 12);

  ({
    EntryHistoryCoordinator coordinator,
    _FakeVaultKdbxService service,
    FakeDatabaseFileRepository files,
  })
  build({bool locked = false}) {
    final service = _FakeVaultKdbxService();
    final files = FakeDatabaseFileRepository();
    final holder = SessionSecretHolder();
    if (!locked) holder.set('secret');
    return (
      coordinator: EntryHistoryCoordinator(
        vaultKdbxService: service,
        sessionSecretHolder: holder,
        databaseFileRepository: files,
      ),
      service: service,
      files: files,
    );
  }

  group('restore', () {
    test('a locked session writes nothing and reports vaultLocked', () async {
      final (:coordinator, :service, files: _) = build(locked: true);

      final result = await coordinator.restore(
        databasePath: '/tmp/v.kdbx',
        entryId: 'e1',
        replacedAt: replacedAt,
      );

      expect(result.outcome, EntryHistoryOutcome.vaultLocked);
      expect(service.restores, isEmpty);
    });

    test('a successful restore reports done', () async {
      final (:coordinator, :service, files: _) = build();

      final result = await coordinator.restore(
        databasePath: '/tmp/v.kdbx',
        entryId: 'e1',
        replacedAt: replacedAt,
      );

      expect(result.outcome, EntryHistoryOutcome.done);
      expect(service.restores, [('e1', replacedAt)]);
    });

    test('a failing write reports failed', () async {
      final (:coordinator, :service, files: _) = build();
      service.restoreError = StateError('no such revision');

      final result = await coordinator.restore(
        databasePath: '/tmp/v.kdbx',
        entryId: 'e1',
        replacedAt: replacedAt,
      );

      expect(result.outcome, EntryHistoryOutcome.failed);
    });
  });

  group('clearHistory', () {
    late Directory tempDir;
    late String databasePath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('entry_history_');
      databasePath = '${tempDir.path}/vault.kdbx';
      await File(databasePath).writeAsBytes(const [1, 2, 3], flush: true);
    });

    tearDown(() => tempDir.delete(recursive: true));

    List<File> backups() => tempDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.contains('.pre-clear-history.kdbx'))
        .toList();

    test('a locked session writes neither a backup nor the file', () async {
      final (:coordinator, :service, :files) = build(locked: true);

      final result = await coordinator.clearHistory(
        databasePath: databasePath,
        entryId: 'e1',
      );

      expect(result.outcome, EntryHistoryOutcome.vaultLocked);
      expect(result.backupPath, isNull);
      expect(files.copiedFiles, isEmpty);
      expect(service.clears, isEmpty);
      expect(backups(), isEmpty);
    });

    // FR-010 / Constitution VII: the backup exists before the service is
    // called, and it is a copy of the pre-clear bytes.
    test('the dated backup exists before the service is called', () async {
      final (:coordinator, :service, files: _) = build();
      List<File>? backupsAtClear;
      service.onClear = () => backupsAtClear = backups();

      final result = await coordinator.clearHistory(
        databasePath: databasePath,
        entryId: 'e1',
      );

      expect(result.outcome, EntryHistoryOutcome.done);
      expect(service.clears, ['e1']);
      expect(backupsAtClear, hasLength(1));
      expect(
        RegExp(
          r'vault\.\d{8}-\d{6}-\d{6}\.pre-clear-history\.kdbx$',
        ).hasMatch(backupsAtClear!.single.path),
        isTrue,
        reason: backupsAtClear!.single.path,
      );
      expect(result.backupPath, backupsAtClear!.single.path);
      expect(await backupsAtClear!.single.readAsBytes(), [1, 2, 3]);
    });

    test(
      'a failing write leaves the backup in place and reports its path',
      () async {
        final (:coordinator, :service, files: _) = build();
        service.clearError = Exception('writer unavailable');

        final result = await coordinator.clearHistory(
          databasePath: databasePath,
          entryId: 'e1',
        );

        expect(result.outcome, EntryHistoryOutcome.failed);
        expect(backups(), hasLength(1));
        expect(result.backupPath, backups().single.path);
      },
    );

    test('a backup that cannot be written stops the clear', () async {
      final (:coordinator, :service, files: _) = build();

      final result = await coordinator.clearHistory(
        databasePath: '${tempDir.path}/missing.kdbx',
        entryId: 'e1',
      );

      expect(result.outcome, EntryHistoryOutcome.failed);
      expect(result.backupPath, isNull);
      expect(service.clears, isEmpty);
    });
  });
}
