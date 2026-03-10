import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/vault_csv_import_service.dart';

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
}

Future<File> _writeTempCsv(String content) async {
  final dir = await Directory.systemTemp.createTemp('vault_csv_import_test_');
  final file = File('${dir.path}/import.csv');
  return file.writeAsString(content, flush: true);
}
