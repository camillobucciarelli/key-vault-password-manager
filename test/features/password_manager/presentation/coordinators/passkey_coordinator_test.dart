import 'dart:math';
// spec 023 T204 — the delete sequence, with fakes: a locked session writes
// nothing; the dated backup precedes the delete; a failed delete keeps the
// backup and reports it; a passkey that is gone is not an error (FR-010).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/vault_kdbx_service.dart';
import 'package:password_manager/features/password_manager/data/services/passkey_generator.dart';
import 'package:password_manager/features/password_manager/domain/errors/passkey_errors.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_passkey.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/passkey_coordinator.dart';
import 'package:password_manager/features/password_manager/presentation/coordinators/session_secret_holder.dart';

import 'fake_database_ports.dart';

class _FakeVaultKdbxService implements VaultKdbxService {
  final List<(String entryId, String relyingPartyId)> deletes = [];
  final List<(String entryId, VaultPasskey passkey, bool replace)> creates = [];
  Object? deleteError;
  Object? createError;

  /// What the create observed on disk when it ran.
  void Function()? onCreate;

  /// What the delete observed on disk when it ran — the backup's existence
  /// at that instant is what "before" means.
  void Function()? onDelete;

  @override
  Future<void> deletePasskey({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String entryId,
    required String relyingPartyId,
    required Uint8List credentialId,
  }) async {
    onDelete?.call();
    if (deleteError != null) throw deleteError!;
    deletes.add((entryId, relyingPartyId));
  }

  @override
  Future<void> createPasskey({
    required String databasePath,
    required String password,
    String? keyFilePath,
    required String entryId,
    required VaultPasskey passkey,
    bool replaceExisting = false,
  }) async {
    onCreate?.call();
    if (createError != null) throw createError!;
    creates.add((entryId, passkey, replaceExisting));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final credentialId = Uint8List.fromList([9, 8, 7]);

  ({
    PasskeyCoordinator coordinator,
    _FakeVaultKdbxService service,
    FakeDatabaseFileRepository files,
  })
  build({bool locked = false}) {
    final service = _FakeVaultKdbxService();
    final files = FakeDatabaseFileRepository();
    final holder = SessionSecretHolder();
    if (!locked) holder.set('secret');
    return (
      coordinator: PasskeyCoordinator(
        vaultKdbxService: service,
        sessionSecretHolder: holder,
        databaseFileRepository: files,
        // Fixed seed: these tests are about sequencing, not randomness.
        generator: PasskeyGenerator(random: Random(7)),
      ),
      service: service,
      files: files,
    );
  }

  late Directory tempDir;
  late String databasePath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('passkey_coordinator_');
    databasePath = '${tempDir.path}/vault.kdbx';
    await File(databasePath).writeAsBytes(const [1, 2, 3], flush: true);
  });

  tearDown(() => tempDir.delete(recursive: true));

  List<File> backups() => tempDir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.contains('.pre-delete-passkey.kdbx'))
      .toList();

  Future<PasskeyDeleteResult> run(PasskeyCoordinator coordinator) =>
      coordinator.deletePasskey(
        databasePath: databasePath,
        entryId: 'e1',
        relyingPartyId: 'webauthn.io',
        credentialId: credentialId,
      );

  test('a locked session writes neither a backup nor the file', () async {
    final (:coordinator, :service, files: _) = build(locked: true);

    final result = await run(coordinator);

    expect(result.outcome, PasskeyOutcome.vaultLocked);
    expect(result.backupPath, isNull);
    expect(service.deletes, isEmpty);
    expect(backups(), isEmpty);
  });

  test('the backup exists on disk before the delete runs', () async {
    final (:coordinator, :service, files: _) = build();
    var backupsWhenDeleteRan = -1;
    service.onDelete = () => backupsWhenDeleteRan = backups().length;

    final result = await run(coordinator);

    expect(result.outcome, PasskeyOutcome.done);
    expect(service.deletes, [('e1', 'webauthn.io')]);
    expect(
      backupsWhenDeleteRan,
      1,
      reason: 'Constitution VII: the copy is written first, not after',
    );
    expect(result.backupPath, isNotNull);
  });

  test('a backup that cannot be written stops the delete', () async {
    final (:coordinator, :service, files: _) = build();

    // A source that is not there: the copy throws, so nothing is destroyed.
    final result = await coordinator.deletePasskey(
      databasePath: '${tempDir.path}/missing.kdbx',
      entryId: 'e1',
      relyingPartyId: 'webauthn.io',
      credentialId: credentialId,
    );

    expect(result.outcome, PasskeyOutcome.failed);
    expect(result.backupPath, isNull);
    expect(service.deletes, isEmpty);
  });

  test('a failed delete keeps the backup and names it', () async {
    final (:coordinator, :service, files: _) = build();
    service.deleteError = StateError('save failed');

    final result = await run(coordinator);

    expect(result.outcome, PasskeyOutcome.failed);
    expect(result.backupPath, isNotNull);
    expect(backups(), hasLength(1));
  });

  group('createPasskey (US3)', () {
    Future<PasskeyCreateResult> create(
      PasskeyCoordinator coordinator, {
      bool replaceExisting = false,
      String? path,
    }) => coordinator.createPasskey(
      databasePath: path ?? databasePath,
      entryId: 'e1',
      relyingPartyId: 'webauthn.io',
      username: 'ada',
      replaceExisting: replaceExisting,
    );

    List<File> createBackups() => tempDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.contains('.pre-create-passkey.kdbx'))
        .toList();

    test('a locked session generates and writes nothing', () async {
      final (:coordinator, :service, files: _) = build(locked: true);

      final result = await create(coordinator);

      expect(result.outcome, PasskeyOutcome.vaultLocked);
      expect(result.created, isNull);
      expect(service.creates, isEmpty);
      expect(createBackups(), isEmpty);
    });

    test(
      'the backup exists before the write, and the key comes back',
      () async {
        final (:coordinator, :service, files: _) = build();
        var backupsWhenCreateRan = -1;
        service.onCreate = () => backupsWhenCreateRan = createBackups().length;

        final result = await create(coordinator);

        expect(result.outcome, PasskeyOutcome.done);
        expect(
          backupsWhenCreateRan,
          1,
          reason: 'Constitution VII: the copy is written first',
        );
        final (entryId, passkey, replace) = service.creates.single;
        expect(entryId, 'e1');
        expect(passkey.relyingPartyId, 'webauthn.io');
        expect(passkey.username, 'ada');
        expect(passkey.algorithm, VaultPasskeyAlgorithm.es256);
        expect(replace, isFalse);
        // The caller needs the public half to answer the relying party.
        expect(result.created!.attestationObject, isNotEmpty);
        expect(result.created!.publicKeyCose, hasLength(77));
      },
    );

    // FR-020: the site must never be told about a credential the vault does
    // not hold, so a failed write yields no GeneratedPasskey at all.
    test('a failed write returns no credential to report', () async {
      final (:coordinator, :service, files: _) = build();
      service.createError = StateError('save failed');

      final result = await create(coordinator);

      expect(result.outcome, PasskeyOutcome.failed);
      expect(result.created, isNull);
      expect(result.backupPath, isNotNull);
    });

    // FR-019: a clash is reported, not overwritten.
    test('a clash reports alreadyExists and writes nothing', () async {
      final (:coordinator, :service, files: _) = build();
      service.createError = const PasskeyAlreadyExists(
        entryId: 'e1',
        relyingPartyId: 'webauthn.io',
      );

      final result = await create(coordinator);

      expect(result.outcome, PasskeyOutcome.alreadyExists);
      expect(result.created, isNull);
    });

    test('replaceExisting is forwarded, never assumed', () async {
      final (:coordinator, :service, files: _) = build();

      await create(coordinator, replaceExisting: true);

      expect(service.creates.single.$3, isTrue);
    });

    test('a backup that cannot be written stops the creation', () async {
      final (:coordinator, :service, files: _) = build();

      final result = await create(
        coordinator,
        path: '${tempDir.path}/missing.kdbx',
      );

      expect(result.outcome, PasskeyOutcome.failed);
      expect(result.backupPath, isNull);
      expect(service.creates, isEmpty);
    });
  });

  test('a passkey that is already gone reports notFound, not failed', () async {
    final (:coordinator, :service, files: _) = build();
    service.deleteError = const PasskeyNotFound(
      entryId: 'e1',
      relyingPartyId: 'webauthn.io',
    );

    final result = await run(coordinator);

    expect(result.outcome, PasskeyOutcome.notFound);
    expect(result.backupPath, isNotNull);
  });
}
