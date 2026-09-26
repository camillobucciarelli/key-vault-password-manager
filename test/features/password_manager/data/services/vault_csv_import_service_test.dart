import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/vault_csv_import_service.dart';

/// A password-shaped column has to be in these fixtures — the parser's job is
/// to map one — but it does not have to look like a credential. The secret
/// scanners read `username,password` adjacency in a CSV row as a leaked login
/// and open an incident per commit; a marker keeps the fixture honest and the
/// scanners quiet.
const _fixturePassword = 'KEYVAULT-FIXTURE-PASSWORD-VALUE';

void main() {
  late VaultCsvImportService service;

  setUp(() {
    service = VaultCsvImportService();
  });

  test('detects Bitwarden format and maps core fields', () async {
    final csv = [
      'folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp',
      'Personal,0,login,GitHub,Personal account,,0,https://github.com,john,secret,otpauth://totp/app?secret=ABC',
    ].join('\n');

    final file = await _writeTempCsv(csv);
    addTearDown(() => file.parent.delete(recursive: true));

    final result = await service.parseFile(file.path);

    expect(result.format, VaultCsvSourceFormat.bitwarden);
    expect(result.totalRows, 1);
    expect(result.skippedRows, 0);
    expect(result.items, hasLength(1));
    expect(result.items.first.title, 'GitHub');
    expect(result.items.first.username, 'john');
    expect(result.items.first.password, 'secret');
    expect(result.items.first.url, 'https://github.com');
    expect(result.items.first.customFields.any((f) => f.key == 'otp'), isTrue);
  });

  test('supports Apple Passwords format with semicolon delimiter', () async {
    final csv = [
      'Title;URL;Username;Password;OTPAuth;Notes',
      'iCloud;https://icloud.com;alice;pwd123;otpauth://totp/example?secret=XYZ;Apple entry',
    ].join('\n');

    final file = await _writeTempCsv(csv);
    addTearDown(() => file.parent.delete(recursive: true));

    final result = await service.parseFile(file.path);

    expect(result.format, VaultCsvSourceFormat.applePasswords);
    expect(result.items, hasLength(1));
    expect(result.items.first.title, 'iCloud');
    expect(result.items.first.notes, 'Apple entry');
    expect(result.items.first.customFields.any((f) => f.key == 'otp'), isTrue);
  });

  test('ignores blank lines', () async {
    final csv = [
      'name,url,username,password,notes',
      '',
      'Google,https://google.com,me@example.com,pass,',
    ].join('\n');

    final file = await _writeTempCsv(csv);
    addTearDown(() => file.parent.delete(recursive: true));

    final result = await service.parseFile(file.path);

    expect(result.totalRows, 1);
    expect(result.items, hasLength(1));
  });

  test('stores non standard columns into custom fields', () async {
    final csv = [
      'name,url,username,password,notes,category,tags',
      'Forum,https://forum.test,bob,pwd,hello,community,work|urgent',
    ].join('\n');

    final file = await _writeTempCsv(csv);
    addTearDown(() => file.parent.delete(recursive: true));

    final result = await service.parseFile(file.path);

    expect(result.items, hasLength(1));
    final fields = result.items.first.customFields;
    expect(
      fields.any((f) => f.key == 'category' && f.value == 'community'),
      isTrue,
    );
    expect(
      fields.any((f) => f.key == 'tags' && f.value == 'work|urgent'),
      isTrue,
    );
  });

  group('spec 023 T208 — a CSV cannot inject passkey fields', () {
    test('a KPEX_PASSKEY_ column is dropped and reported', () async {
      final csv = [
        'name,url,username,password,KPEX_PASSKEY_PRIVATE_KEY_PEM',
        'Example,https://example.com,alice,$_fixturePassword,SHOULD-NEVER-LAND',
      ].join('\n');

      final file = await _writeTempCsv(csv);
      addTearDown(() => file.parent.delete(recursive: true));

      final result = await service.parseFile(file.path);

      expect(result.items, hasLength(1));
      final item = result.items.single;
      expect(item.title, 'Example');
      expect(item.password, _fixturePassword);
      expect(
        item.customFields.map((field) => field.key),
        isNot(contains('KPEX_PASSKEY_PRIVATE_KEY_PEM')),
      );
      // The value must not survive under any key, not merely under its own.
      expect(
        item.customFields.map((field) => field.value),
        isNot(contains('SHOULD-NEVER-LAND')),
      );
      expect(result.ignoredColumns, hasLength(1));
      expect(
        result.ignoredColumns.single.header,
        'KPEX_PASSKEY_PRIVATE_KEY_PEM',
      );
      expect(result.ignoredColumns.single.reason, contains('Passkey'));
    });

    test('the whole namespace is refused, not just the private key', () async {
      final csv = [
        'name,username,password,'
            'KPEX_PASSKEY_RELYING_PARTY,KPEX_PASSKEY_USERNAME,'
            'KPEX_PASSKEY_CREDENTIAL_ID,KPEX_PASSKEY_USER_HANDLE',
        'Example,alice,$_fixturePassword,example.com,alice,Y3JlZA,dXNlcg',
      ].join('\n');

      final file = await _writeTempCsv(csv);
      addTearDown(() => file.parent.delete(recursive: true));

      final result = await service.parseFile(file.path);

      expect(result.items.single.customFields, isEmpty);
      expect(result.ignoredColumns, hasLength(4));
    });

    test('punctuation and case do not get a header through', () async {
      final csv = [
        'name,username,password,kpex-passkey-private-key-pem,'
            'Kpex Passkey Credential Id',
        'Example,alice,$_fixturePassword,LEAK-1,LEAK-2',
      ].join('\n');

      final file = await _writeTempCsv(csv);
      addTearDown(() => file.parent.delete(recursive: true));

      final result = await service.parseFile(file.path);

      expect(result.items.single.customFields, isEmpty);
      expect(
        result.ignoredColumns.map((column) => column.header),
        containsAll(<String>[
          'kpex-passkey-private-key-pem',
          'Kpex Passkey Credential Id',
        ]),
      );
    });

    test('an ordinary column that merely mentions a passkey is kept', () async {
      final csv = [
        'name,username,password,Passkey notes,kpex_other',
        'Example,alice,$_fixturePassword,recovery hint,kept',
      ].join('\n');

      final file = await _writeTempCsv(csv);
      addTearDown(() => file.parent.delete(recursive: true));

      final result = await service.parseFile(file.path);

      expect(result.ignoredColumns, isEmpty);
      expect(
        result.items.single.customFields.map((field) => field.key),
        containsAll(<String>['Passkey notes', 'kpex_other']),
      );
    });

    test('a file without reserved columns reports none', () async {
      final csv = [
        'name,url,username,password,notes',
        'Example,https://example.com,alice,$_fixturePassword,hello',
      ].join('\n');

      final file = await _writeTempCsv(csv);
      addTearDown(() => file.parent.delete(recursive: true));

      final result = await service.parseFile(file.path);

      expect(result.ignoredColumns, isEmpty);
    });
  });
}

Future<File> _writeTempCsv(String content) async {
  final dir = await Directory.systemTemp.createTemp('vault_csv_import_test_');
  final file = File('${dir.path}/import.csv');
  return file.writeAsString(content, flush: true);
}
