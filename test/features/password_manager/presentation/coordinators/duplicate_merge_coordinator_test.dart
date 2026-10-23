// spec 023 T207 — the merge sequence, with fakes: a locked session writes
// nothing; the backup precedes the merge; a passkey conflict refuses without
// writing; a failed merge leaves the backup and reports it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/vault_kdbx_service.dart';
import 'package:password_manager/features/password_manager/domain/errors/passkey_errors.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/duplicate_merge_coordinator.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/session_secret_holder.dart';

import 'fake_database_ports.dart';

class _FakeVaultKdbxService implements VaultKdbxService {
  final List<({String primaryId, List<String> secondaryIds})> merges = [];
  Object? mergeError;

  /// What the merge observed on disk when it ran — the backup's existence at
  /// that instant is what "before" means.
  void Function()? onMerge;

  @override
  Future<void> mergeEntries({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String primaryId,
    required List<String> secondaryIds,
  }) async {
    onMerge?.call();
    if (mergeError != null) throw mergeError!;
    merges.add((primaryId: primaryId, secondaryIds: secondaryIds));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tempDir;
  late String databasePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('merge_coordinator_test_');
    databasePath = '${tempDir.path}/vault.kdbx';
    await File(databasePath).writeAsBytes(const [1, 2, 3], flush: true);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  ({
    DuplicateMergeCoordinator coordinator,
    _FakeVaultKdbxService service,
    FakeDatabaseFileRepository files,
  })
  build({bool locked = false}) {
    final service = _FakeVaultKdbxService();
    final files = FakeDatabaseFileRepository();
    final holder = SessionSecretHolder();
    if (!locked) holder.set('secret');
    return (
      coordinator: DuplicateMergeCoordinator(
        vaultKdbxService: service,
        sessionSecretHolder: holder,
        databaseFileRepository: files,
      ),
      service: service,
      files: files,
    );
  }

  test('a locked session writes nothing and reports vaultLocked', () async {
    final (:coordinator, :service, :files) = build(locked: true);

    final result = await coordinator.merge(
      databasePath: databasePath,
      primaryId: 'p',
      secondaryIds: const ['s'],
    );

    expect(result.outcome, DuplicateMergeOutcome.vaultLocked);
    expect(result.backupPath, isNull);
    expect(service.merges, isEmpty);
    expect(files.copiedFiles, isEmpty);
  });

  test('a dated pre-merge copy is written and the merge runs', () async {
    final (:coordinator, :service, files: _) = build();

    final result = await coordinator.merge(
      databasePath: databasePath,
      primaryId: 'p',
      secondaryIds: const ['s1', 's2'],
    );

    expect(result.outcome, DuplicateMergeOutcome.done);
    expect(result.backupPath, contains('pre-merge'));
    expect(File(result.backupPath!).existsSync(), isTrue);
    expect(service.merges.single.secondaryIds, ['s1', 's2']);
  });

  test('the copy is on disk by the time the merge runs', () async {
    final (:coordinator, :service, :files) = build();
    // Read inside the merge call, so this is the real ordering and not what
    // the result happened to report afterwards.
    var backupOnDiskDuringMerge = false;
    service.onMerge = () {
      final copied = files.copiedFiles;
      backupOnDiskDuringMerge =
          copied.length == 1 && File(copied.single.targetPath).existsSync();
    };

    await coordinator.merge(
      databasePath: databasePath,
      primaryId: 'p',
      secondaryIds: const ['s'],
    );

    expect(backupOnDiskDuringMerge, isTrue);
  });

  test('a backup that cannot be written stops the merge', () async {
    final (:coordinator, :service, files: _) = build();

    final result = await coordinator.merge(
      databasePath: '${tempDir.path}/missing.kdbx',
      primaryId: 'p',
      secondaryIds: const ['s'],
    );

    expect(result.outcome, DuplicateMergeOutcome.failed);
    expect(result.backupPath, isNull);
    expect(service.merges, isEmpty);
  });

  test(
    'a passkey conflict reports the relying party and writes nothing',
    () async {
      final (:coordinator, :service, files: _) = build();
      service.mergeError = const PasskeyMergeConflict(
        primaryId: 'p',
        secondaryId: 's',
        relyingPartyId: 'webauthn.io',
      );

      final result = await coordinator.merge(
        databasePath: databasePath,
        primaryId: 'p',
        secondaryIds: const ['s'],
      );

      expect(result.outcome, DuplicateMergeOutcome.passkeyConflict);
      expect(result.relyingPartyId, 'webauthn.io');
      // The spare copy is still reported: a file next to the vault is never a
      // surprise, even when nothing was changed.
      expect(result.backupPath, isNotNull);
      expect(service.merges, isEmpty);
    },
  );

  test('a failed merge keeps and reports the backup', () async {
    final (:coordinator, :service, files: _) = build();
    service.mergeError = StateError('writer unavailable');

    final result = await coordinator.merge(
      databasePath: databasePath,
      primaryId: 'p',
      secondaryIds: const ['s'],
    );

    expect(result.outcome, DuplicateMergeOutcome.failed);
    expect(result.backupPath, isNotNull);
    expect(File(result.backupPath!).existsSync(), isTrue);
  });
}
