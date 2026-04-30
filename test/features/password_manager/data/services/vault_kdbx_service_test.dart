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
}) async {
  final credentials = Credentials.composite(
    ProtectedValue.fromString(password),
    null,
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
