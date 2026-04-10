import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_custom_field.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';
import 'package:password_manager/features/password_manager/domain/services/vault_autofill_matcher.dart';

void main() {
  group('VaultAutofillMatcher', () {
    final matcher = VaultAutofillMatcher();

    test('prefers exact domain match over subdomain', () {
      final entries = [
        _entry(
          id: '1',
          title: 'Example exact',
          username: 'alice',
          password: 'pw1',
          url: 'https://example.com/login',
        ),
        _entry(
          id: '2',
          title: 'Example sub',
          username: 'alice',
          password: 'pw2',
          url: 'https://auth.example.com',
        ),
      ];

      final results = matcher.findBestMatches(
        entries: entries,
        webDomains: {'example.com'},
      );

      expect(results.first.id, '1');
    });

    test('normalizes mobile and www prefixes in domain matching', () {
      final entries = [
        _entry(
          id: '1',
          title: 'Mobile',
          username: 'alice',
          password: 'pw1',
          url: 'https://mobile.example.com',
        ),
      ];

      final results = matcher.findBestMatches(
        entries: entries,
        webDomains: {'www.example.com'},
      );

      expect(results, hasLength(1));
      expect(results.first.id, '1');
    });

    test('matches android package names from custom fields', () {
      final entries = [
        _entry(
          id: '1',
          title: 'Bank app',
          username: 'alice',
          password: 'pw1',
          customFields: const [
            VaultCustomField(key: 'androidPackage', value: 'com.bank.app'),
          ],
        ),
        _entry(
          id: '2',
          title: 'Other app',
          username: 'alice',
          password: 'pw2',
          customFields: const [
            VaultCustomField(key: 'androidPackage', value: 'com.other.app'),
          ],
        ),
      ];

      final results = matcher.findBestMatches(
        entries: entries,
        packageNames: {'com.bank.app'},
      );

      expect(results.first.id, '1');
    });

    test('matches androidapp:// URL scheme as package identifier', () {
      final entries = [
        _entry(
          id: '1',
          title: 'Bank',
          username: 'alice',
          password: 'pw',
          url: 'androidapp://com.example.bank',
        ),
      ];

      final results = matcher.findBestMatches(
        entries: entries,
        packageNames: {'com.example.bank'},
      );

      expect(results, hasLength(1));
      expect(results.first.id, '1');
    });

    test('matches iosbundleid:// URL scheme as package identifier', () {
      final entries = [
        _entry(
          id: '1',
          title: 'Bank iOS',
          username: 'alice',
          password: 'pw',
          url: 'iosbundleid://com.example.bank',
        ),
      ];

      final results = matcher.findBestMatches(
        entries: entries,
        packageNames: {'com.example.bank'},
      );

      expect(results, hasLength(1));
      expect(results.first.id, '1');
    });

    test('matches KPH: androidPackage custom field', () {
      final entries = [
        _entry(
          id: '1',
          title: 'Bank',
          username: 'alice',
          password: 'pw',
          url: '',
          customFields: [
            const VaultCustomField(key: 'KPH: androidPackage', value: 'com.example.bank'),
          ],
        ),
      ];

      final results = matcher.findBestMatches(
        entries: entries,
        packageNames: {'com.example.bank'},
      );

      expect(results, hasLength(1));
      expect(results.first.id, '1');
    });

    test('matches KPH: iosBundle custom field', () {
      final entries = [
        _entry(
          id: '1',
          title: 'Bank iOS',
          username: 'alice',
          password: 'pw',
          url: '',
          customFields: [
            const VaultCustomField(key: 'KPH: iosBundle', value: 'com.example.bank'),
          ],
        ),
      ];

      final results = matcher.findBestMatches(
        entries: entries,
        packageNames: {'com.example.bank'},
      );

      expect(results, hasLength(1));
      expect(results.first.id, '1');
    });
  });
}

VaultEntry _entry({
  required String id,
  required String title,
  required String username,
  required String password,
  String url = '',
  List<VaultCustomField> customFields = const [],
  DateTime? updatedAt,
}) {
  return VaultEntry(
    id: id,
    groupId: 'root',
    title: title,
    username: username,
    password: password,
    url: url,
    notes: '',
    customFields: customFields,
    updatedAt: updatedAt ?? DateTime.utc(2026, 1, 1),
  );
}
