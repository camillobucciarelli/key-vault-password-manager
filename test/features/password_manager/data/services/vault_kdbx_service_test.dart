import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kdbx/kdbx.dart';
import 'package:password_manager/features/password_manager/data/services/vault_kdbx_service.dart';

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
