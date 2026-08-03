import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kdbx/kdbx.dart';
import 'package:password_manager/features/password_manager/data/services/vault_kdbx_service.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_custom_field.dart';

void main() {
  const password = 'test-password';

  late VaultKdbxService service;
  late Directory tempDir;
  late String databasePath;

  setUp(() async {
    service = VaultKdbxService();
    tempDir = await Directory.systemTemp.createTemp('vault_kdbx_service_test_');
    databasePath = '${tempDir.path}/vault.kdbx';
    await _createDatabase(databasePath: databasePath, password: password);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('changes password and key file together', () async {
    final keyFile = File('${tempDir.path}/vault.key');
    await keyFile.writeAsBytes(List<int>.generate(64, (index) => index));

    await service.changeCredentials(
      databasePath: databasePath,
      currentPassword: password,
      newPassword: 'new-password',
      newKeyFilePath: keyFile.path,
    );

    await expectLater(
      service.loadVault(
        databasePath: databasePath,
        password: 'new-password',
        keyFilePath: keyFile.path,
      ),
      completes,
    );
    await expectLater(
      service.loadVault(databasePath: databasePath, password: password),
      throwsA(anything),
    );
  });

  test('changes password only and rejects old password', () async {
    await service.changeCredentials(
      databasePath: databasePath,
      currentPassword: password,
      newPassword: 'new-password',
    );

    await expectLater(
      service.loadVault(databasePath: databasePath, password: 'new-password'),
      completes,
    );
    await expectLater(
      service.loadVault(databasePath: databasePath, password: password),
      throwsA(anything),
    );
  });

  test('adds, changes, and removes key file atomically', () async {
    final firstKey = File('${tempDir.path}/first.key');
    final secondKey = File('${tempDir.path}/second.key');
    await firstKey.writeAsBytes(List<int>.filled(64, 1));
    await secondKey.writeAsBytes(List<int>.filled(64, 2));

    await service.changeCredentials(
      databasePath: databasePath,
      currentPassword: password,
      newPassword: password,
      newKeyFilePath: firstKey.path,
    );
    await expectLater(
      service.loadVault(
        databasePath: databasePath,
        password: password,
        keyFilePath: firstKey.path,
      ),
      completes,
    );

    await service.changeCredentials(
      databasePath: databasePath,
      currentPassword: password,
      currentKeyFilePath: firstKey.path,
      newPassword: password,
      newKeyFilePath: secondKey.path,
    );
    await expectLater(
      service.loadVault(
        databasePath: databasePath,
        password: password,
        keyFilePath: secondKey.path,
      ),
      completes,
    );
    await expectLater(
      service.loadVault(
        databasePath: databasePath,
        password: password,
        keyFilePath: firstKey.path,
      ),
      throwsA(anything),
    );

    await service.changeCredentials(
      databasePath: databasePath,
      currentPassword: password,
      currentKeyFilePath: secondKey.path,
      newPassword: password,
    );
    await expectLater(
      service.loadVault(databasePath: databasePath, password: password),
      completes,
    );
    await expectLater(
      service.loadVault(
        databasePath: databasePath,
        password: password,
        keyFilePath: secondKey.path,
      ),
      throwsA(anything),
    );
  });

  test('changes key-only vault and removes key by adding password', () async {
    final firstKey = File('${tempDir.path}/key-only-first.key');
    final secondKey = File('${tempDir.path}/key-only-second.key');
    await firstKey.writeAsBytes(List<int>.filled(64, 3));
    await secondKey.writeAsBytes(List<int>.filled(64, 4));
    await _createDatabase(
      databasePath: databasePath,
      password: '',
      keyFilePath: firstKey.path,
    );

    await service.changeCredentials(
      databasePath: databasePath,
      currentPassword: '',
      currentKeyFilePath: firstKey.path,
      newPassword: '',
      newKeyFilePath: secondKey.path,
    );
    await expectLater(
      service.loadVault(
        databasePath: databasePath,
        password: '',
        keyFilePath: secondKey.path,
      ),
      completes,
    );

    await service.changeCredentials(
      databasePath: databasePath,
      currentPassword: '',
      currentKeyFilePath: secondKey.path,
      newPassword: 'fallback-password',
    );
    await expectLater(
      service.loadVault(
        databasePath: databasePath,
        password: 'fallback-password',
      ),
      completes,
    );
  });

  test('wrong current credentials leave original database readable', () async {
    final originalBytes = await File(databasePath).readAsBytes();

    await expectLater(
      service.beginCredentialChange(
        databasePath: databasePath,
        currentPassword: 'wrong-password',
        newPassword: 'new-password',
      ),
      throwsA(anything),
    );

    expect(await File(databasePath).readAsBytes(), originalBytes);
    await expectLater(
      service.loadVault(databasePath: databasePath, password: password),
      completes,
    );
  });

  test('write failure leaves original database untouched', () async {
    final originalBytes = await File(databasePath).readAsBytes();
    final failingService = VaultKdbxService(
      credentialTempWriter: (_, _) async => throw FileSystemException('write'),
    );

    await expectLater(
      failingService.beginCredentialChange(
        databasePath: databasePath,
        currentPassword: password,
        newPassword: 'new-password',
      ),
      throwsA(isA<FileSystemException>()),
    );

    expect(await File(databasePath).readAsBytes(), originalBytes);
  });

  test(
    'truncated temp file fails verification without replacing original',
    () async {
      final originalBytes = await File(databasePath).readAsBytes();
      final truncatingService = VaultKdbxService(
        credentialTempWriter: (file, _) =>
            file.writeAsBytes(const [1, 2, 3], flush: true),
      );

      await expectLater(
        truncatingService.beginCredentialChange(
          databasePath: databasePath,
          currentPassword: password,
          newPassword: 'new-password',
        ),
        throwsA(anything),
      );

      expect(await File(databasePath).readAsBytes(), originalBytes);
    },
  );

  test('credential rollback restores old credentials', () async {
    final change = await service.beginCredentialChange(
      databasePath: databasePath,
      currentPassword: password,
      newPassword: 'new-password',
    );
    await expectLater(
      service.loadVault(databasePath: databasePath, password: 'new-password'),
      completes,
    );

    await service.rollbackCredentialChange(change);

    await expectLater(
      service.loadVault(databasePath: databasePath, password: password),
      completes,
    );
    await expectLater(
      service.loadVault(databasePath: databasePath, password: 'new-password'),
      throwsA(anything),
    );
  });

  test('maps created and modified timestamps for new entries', () async {
    final rootGroupId = await _rootGroupId(service, databasePath, password);
    await service.createEntry(
      databasePath: databasePath,
      password: password,
      groupId: rootGroupId,
      title: 'GitHub',
      username: 'camillo',
      entryPassword: 'p@ss-1',
      url: 'https://github.com',
      notes: 'note',
    );

    final entries = await service.loadAllEntries(
      databasePath: databasePath,
      password: password,
    );
    final entry = entries.single;

    expect(entry.createdAt, isNotNull);
    expect(entry.updatedAt, isNotNull);
    expect(entry.lastPasswordChangedAt, entry.createdAt);
  });

  test(
    'keeps password change timestamp at creation when password does not change',
    () async {
      final rootGroupId = await _rootGroupId(service, databasePath, password);
      await service.createEntry(
        databasePath: databasePath,
        password: password,
        groupId: rootGroupId,
        title: 'Mail',
        username: 'user',
        entryPassword: 'same-password',
        url: '',
        notes: '',
      );

      final first = (await service.loadAllEntries(
        databasePath: databasePath,
        password: password,
      )).single;

      await service.updateEntry(
        databasePath: databasePath,
        password: password,
        entryId: first.id,
        title: 'Mail Personal',
        username: first.username,
        entryPassword: first.password,
        url: first.url,
        notes: first.notes,
        customFields: first.customFields,
      );

      final updated = (await service.loadAllEntries(
        databasePath: databasePath,
        password: password,
      )).single;

      expect(updated.lastPasswordChangedAt, first.createdAt);
    },
  );

  test(
    'sets last password change timestamp to update timestamp when password changes',
    () async {
      final rootGroupId = await _rootGroupId(service, databasePath, password);
      await service.createEntry(
        databasePath: databasePath,
        password: password,
        groupId: rootGroupId,
        title: 'Bank',
        username: 'user',
        entryPassword: 'old-password',
        url: '',
        notes: '',
      );

      final first = (await service.loadAllEntries(
        databasePath: databasePath,
        password: password,
      )).single;

      await service.updateEntry(
        databasePath: databasePath,
        password: password,
        entryId: first.id,
        title: first.title,
        username: first.username,
        entryPassword: 'new-password',
        url: first.url,
        notes: first.notes,
        customFields: first.customFields,
      );

      final updated = (await service.loadAllEntries(
        databasePath: databasePath,
        password: password,
      )).single;

      expect(updated.lastPasswordChangedAt, updated.updatedAt);
    },
  );

  test(
    'updateEntry persists changed title, username, password, url, notes',
    () async {
      final rootGroupId = await _rootGroupId(service, databasePath, password);
      await service.createEntry(
        databasePath: databasePath,
        password: password,
        groupId: rootGroupId,
        title: 'Original Title',
        username: 'original_user',
        entryPassword: 'original_pass',
        url: 'https://original.com',
        notes: 'original notes',
      );

      final original = (await service.loadAllEntries(
        databasePath: databasePath,
        password: password,
      )).single;

      await service.updateEntry(
        databasePath: databasePath,
        password: password,
        entryId: original.id,
        title: 'Updated Title',
        username: 'updated_user',
        entryPassword: 'updated_pass',
        url: 'https://updated.com',
        notes: 'updated notes',
      );

      final updated = (await service.loadAllEntries(
        databasePath: databasePath,
        password: password,
      )).single;

      expect(updated.title, 'Updated Title');
      expect(updated.username, 'updated_user');
      expect(updated.password, 'updated_pass');
      expect(updated.url, 'https://updated.com');
      expect(updated.notes, 'updated notes');
    },
  );

  group('mergeEntries', () {
    test(
      'copies notes from secondary to primary when primary notes is empty',
      () async {
        final rootGroupId = await _rootGroupId(service, databasePath, password);
        final primaryId = await service.createEntry(
          databasePath: databasePath,
          password: password,
          groupId: rootGroupId,
          title: 'Primary',
          username: 'alice',
          entryPassword: 'pw',
          url: 'https://github.com',
          notes: '',
        );
        final secondaryId = await service.createEntry(
          databasePath: databasePath,
          password: password,
          groupId: rootGroupId,
          title: 'Secondary',
          username: 'alice',
          entryPassword: 'pw',
          url: 'https://github.com',
          notes: 'important note',
        );

        await service.mergeEntries(
          databasePath: databasePath,
          password: password,
          primaryId: primaryId,
          secondaryId: secondaryId,
        );

        final all = await service.loadAllEntries(
          databasePath: databasePath,
          password: password,
        );
        final primary = all.firstWhere((e) => e.id == primaryId);
        expect(primary.notes, 'important note');
      },
    );

    test('does not overwrite primary notes when already set', () async {
      final rootGroupId = await _rootGroupId(service, databasePath, password);
      final primaryId = await service.createEntry(
        databasePath: databasePath,
        password: password,
        groupId: rootGroupId,
        title: 'Primary',
        username: 'alice',
        entryPassword: 'pw',
        url: 'https://github.com',
        notes: 'keep me',
      );
      final secondaryId = await service.createEntry(
        databasePath: databasePath,
        password: password,
        groupId: rootGroupId,
        title: 'Secondary',
        username: 'alice',
        entryPassword: 'pw',
        url: 'https://github.com',
        notes: 'do not copy',
      );

      await service.mergeEntries(
        databasePath: databasePath,
        password: password,
        primaryId: primaryId,
        secondaryId: secondaryId,
      );

      final all = await service.loadAllEntries(
        databasePath: databasePath,
        password: password,
      );
      final primary = all.firstWhere((e) => e.id == primaryId);
      expect(primary.notes, 'keep me');
    });

    test('copies custom field from secondary absent in primary', () async {
      final rootGroupId = await _rootGroupId(service, databasePath, password);
      final primaryId = await service.createEntry(
        databasePath: databasePath,
        password: password,
        groupId: rootGroupId,
        title: 'Primary',
        username: 'alice',
        entryPassword: 'pw',
        url: 'https://github.com',
        notes: '',
        customFields: [const VaultCustomField(key: 'PIN', value: '1234')],
      );
      final secondaryId = await service.createEntry(
        databasePath: databasePath,
        password: password,
        groupId: rootGroupId,
        title: 'Secondary',
        username: 'alice',
        entryPassword: 'pw',
        url: 'https://github.com',
        notes: '',
        customFields: [
          const VaultCustomField(key: 'Recovery', value: 'abc123'),
        ],
      );

      await service.mergeEntries(
        databasePath: databasePath,
        password: password,
        primaryId: primaryId,
        secondaryId: secondaryId,
      );

      final all = await service.loadAllEntries(
        databasePath: databasePath,
        password: password,
      );
      final primary = all.firstWhere((e) => e.id == primaryId);
      final fieldKeys = primary.customFields.map((f) => f.key).toList();
      expect(fieldKeys, containsAll(['PIN', 'Recovery']));
    });

    test('moves secondary to recycle bin after merge', () async {
      final rootGroupId = await _rootGroupId(service, databasePath, password);
      final primaryId = await service.createEntry(
        databasePath: databasePath,
        password: password,
        groupId: rootGroupId,
        title: 'Primary',
        username: 'alice',
        entryPassword: 'pw',
        url: 'https://github.com',
        notes: '',
      );
      final secondaryId = await service.createEntry(
        databasePath: databasePath,
        password: password,
        groupId: rootGroupId,
        title: 'Secondary',
        username: 'alice',
        entryPassword: 'pw',
        url: 'https://github.com',
        notes: '',
      );

      await service.mergeEntries(
        databasePath: databasePath,
        password: password,
        primaryId: primaryId,
        secondaryId: secondaryId,
      );

      final recycleBinEntries = await service.loadRecycleBinEntries(
        databasePath: databasePath,
        password: password,
      );
      expect(recycleBinEntries.map((e) => e.id), contains(secondaryId));

      final all = await service.loadAllEntries(
        databasePath: databasePath,
        password: password,
      );
      final activeIds = all.map((e) => e.id).toSet();
      expect(activeIds, contains(primaryId));
      expect(activeIds, isNot(contains(secondaryId)));
    });

    test('loadVault allEntries excludes entries in recycle bin', () async {
      final rootGroupId = await _rootGroupId(service, databasePath, password);
      final primaryId = await service.createEntry(
        databasePath: databasePath,
        password: password,
        groupId: rootGroupId,
        title: 'Primary',
        username: 'alice',
        entryPassword: 'pw',
        url: 'https://github.com',
        notes: '',
      );
      final secondaryId = await service.createEntry(
        databasePath: databasePath,
        password: password,
        groupId: rootGroupId,
        title: 'Secondary',
        username: 'alice',
        entryPassword: 'pw',
        url: 'https://github.com',
        notes: '',
      );

      await service.mergeEntries(
        databasePath: databasePath,
        password: password,
        primaryId: primaryId,
        secondaryId: secondaryId,
      );

      final snapshot = await service.loadVault(
        databasePath: databasePath,
        password: password,
      );
      final activeIds = snapshot.allEntries.map((e) => e.id).toSet();

      expect(activeIds, contains(primaryId));
      expect(activeIds, isNot(contains(secondaryId)));
    });
  });
}

Future<void> _createDatabase({
  required String databasePath,
  required String password,
  String? keyFilePath,
}) async {
  final keyBytes = keyFilePath == null
      ? null
      : await File(keyFilePath).readAsBytes();
  final credentials = Credentials.composite(
    ProtectedValue.fromString(password),
    keyBytes,
  );
  final kdbx = KdbxFormat().create(credentials, 'Test DB');
  final bytes = await kdbx.save();
  await File(databasePath).writeAsBytes(bytes, flush: true);
}

Future<String> _rootGroupId(
  VaultKdbxService service,
  String databasePath,
  String password,
) async {
  final snapshot = await service.loadVault(
    databasePath: databasePath,
    password: password,
  );
  return snapshot.rootGroupId;
}
