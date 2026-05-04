import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/datasources/ios_autofill_data_source.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_custom_field.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';

void main() {
  group('encodeIosAutofillSnapshot', () {
    test(
      'serializes only fields consumed by the native credential provider',
      () {
        final payload = encodeIosAutofillSnapshot(const [
          VaultEntry(
            id: 'entry-1',
            groupId: 'group-1',
            title: 'Example',
            username: 'alice',
            password: 'secret',
            url: 'https://example.com/login',
            notes: 'note',
            customFields: [
              VaultCustomField(key: 'KPH: iOSBundle', value: 'com.example.app'),
            ],
          ),
        ]);

        final decoded = jsonDecode(payload) as List<dynamic>;

        expect(decoded, hasLength(1));
        expect(decoded.single, {
          'id': 'entry-1',
          'title': 'Example',
          'username': 'alice',
          'password': 'secret',
          'url': 'https://example.com/login',
          'notes': 'note',
          'customFields': [
            {'key': 'KPH: iOSBundle', 'value': 'com.example.app'},
          ],
        });
      },
    );

    test(
      'preserves entries without credentials so native filtering decides visibility',
      () {
        final payload = encodeIosAutofillSnapshot(const [
          VaultEntry(
            id: 'entry-1',
            groupId: 'group-1',
            title: 'Metadata only',
            username: '',
            password: '',
            url: 'example.com',
            notes: '',
          ),
        ]);

        final decoded = jsonDecode(payload) as List<dynamic>;

        expect(decoded, hasLength(1));
        expect(
          (decoded.single as Map<String, dynamic>)['customFields'],
          isEmpty,
        );
      },
    );
  });
}
