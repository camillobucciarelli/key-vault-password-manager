import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/models/autofill_models.dart';
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

      final results = matcher.findCandidates(
        entries: entries,
        request: _webRequest('example.com'),
      );

      expect(results.first.entryId, '1');
    });

    test('normalizes mobile, www, and URLs without scheme', () {
      final entries = [
        _entry(
          id: '1',
          title: 'Mobile',
          username: 'alice',
          password: 'pw1',
          url: 'https://mobile.example.com',
        ),
      ];

      final results = matcher.findCandidates(
        entries: entries,
        request: _webRequest('example.com/login'),
      );

      expect(results, hasLength(1));
      expect(results.first.entryId, '1');
      expect(results.first.webDomain, 'example.com');
    });

    test('does not suggest title-only matches', () {
      final entries = [
        _entry(
          id: '1',
          title: 'example.com',
          username: 'alice',
          password: 'pw1',
          url: '',
        ),
      ];

      final results = matcher.findCandidates(
        entries: entries,
        request: _webRequest('example.com'),
      );

      expect(results, isEmpty);
    });

    test('rejects phishing domain suffixes like example.com.evil.com', () {
      final entries = [
        _entry(
          id: '1',
          title: 'Phishing',
          username: 'alice',
          password: 'pw1',
          url: 'https://example.com.evil.com/login',
        ),
      ];

      final results = matcher.findCandidates(
        entries: entries,
        request: _webRequest('example.com'),
      );

      expect(results, isEmpty);
    });

    test('does not use naive eTLD sibling matching without PSL', () {
      final entries = [
        _entry(
          id: '1',
          title: 'Wrong co.uk sibling',
          username: 'alice',
          password: 'pw1',
          url: 'https://evil.co.uk',
        ),
      ];

      final results = matcher.findCandidates(
        entries: entries,
        request: _webRequest('example.co.uk'),
      );

      expect(results, isEmpty);
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

      final results = matcher.findCandidates(
        entries: entries,
        request: _androidRequest('com.bank.app'),
      );

      expect(results.single.entryId, '1');
      expect(results.single.hasPassword, isTrue);
      expect(results.single.matchedTargets.single.value, 'com.bank.app');
    });

    test('does not match package names by suffix or substring', () {
      final entries = [
        _entry(
          id: '1',
          title: 'Impersonator',
          username: 'alice',
          password: 'pw1',
          customFields: const [
            VaultCustomField(key: 'androidPackage', value: 'com.bank.app.evil'),
          ],
        ),
      ];

      final results = matcher.findCandidates(
        entries: entries,
        request: _androidRequest('com.bank.app'),
      );

      expect(results, isEmpty);
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

      final results = matcher.findCandidates(
        entries: entries,
        request: _androidRequest('com.example.bank'),
      );

      expect(results, hasLength(1));
      expect(results.first.entryId, '1');
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

      final results = matcher.findCandidates(
        entries: entries,
        request: _appleRequest('com.example.bank'),
      );

      expect(results, hasLength(1));
      expect(results.first.entryId, '1');
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
            const VaultCustomField(
              key: 'KPH: androidPackage',
              value: 'com.example.bank',
            ),
          ],
        ),
      ];

      final results = matcher.findCandidates(
        entries: entries,
        request: _androidRequest('com.example.bank'),
      );

      expect(results, hasLength(1));
      expect(results.first.entryId, '1');
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
            const VaultCustomField(
              key: 'KPH: iosBundle',
              value: 'com.example.bank',
            ),
          ],
        ),
      ];

      final results = matcher.findCandidates(
        entries: entries,
        request: _appleRequest('com.example.bank'),
      );

      expect(results, hasLength(1));
      expect(results.first.entryId, '1');
    });

    test('does not return unscoped suggestions with secure defaults', () {
      final entries = [
        _entry(
          id: '1',
          title: 'Example',
          username: 'alice',
          password: 'pw',
          url: 'https://example.com',
        ),
      ];

      final results = matcher.findCandidates(
        entries: entries,
        request: const AutofillRequest(
          id: 'request-1',
          intent: AutofillRequestIntent.fill,
          targets: [],
        ),
      );

      expect(results, isEmpty);
    });
  });
}

AutofillRequest _webRequest(String domainOrUrl) {
  return AutofillRequest(
    id: 'request-$domainOrUrl',
    intent: AutofillRequestIntent.fill,
    targets: [AutofillTarget.webDomain(domainOrUrl)],
  );
}

AutofillRequest _androidRequest(String packageName) {
  return AutofillRequest(
    id: 'request-$packageName',
    intent: AutofillRequestIntent.fill,
    targets: [AutofillTarget.androidPackage(packageName)],
  );
}

AutofillRequest _appleRequest(String bundleId) {
  return AutofillRequest(
    id: 'request-$bundleId',
    intent: AutofillRequestIntent.fill,
    targets: [AutofillTarget.appleBundleId(bundleId)],
  );
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
