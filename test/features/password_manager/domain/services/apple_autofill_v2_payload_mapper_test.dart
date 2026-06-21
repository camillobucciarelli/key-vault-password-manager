import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/models/apple_autofill_v2_models.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_custom_field.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';
import 'package:password_manager/features/password_manager/domain/services/apple_autofill_v2_payload_mapper.dart';

void main() {
  group('AppleAutofillV2PayloadMapper', () {
    const mapper = AppleAutofillV2PayloadMapper();

    test(
      'normalizes URL without scheme into origin and domain identifiers',
      () {
        final credential = mapper.mapEntry(
          _entry(url: 'Example.COM/login?token=ignored'),
        );

        expect(credential, isNotNull);
        expect(credential!.url, 'https://example.com');
        expect(
          credential.serviceIdentifiers,
          containsAll(const [
            AppleAutofillV2ServiceIdentifier.url('https://example.com'),
            AppleAutofillV2ServiceIdentifier.domain('example.com'),
          ]),
        );
      },
    );

    test('normalizes domains and strips mobile/www prefixes', () {
      final credential = mapper.mapEntry(
        _entry(url: 'https://www.Example.com/accounts/login'),
      );

      expect(credential!.url, 'https://example.com');
      expect(
        credential.serviceIdentifiers,
        contains(const AppleAutofillV2ServiceIdentifier.domain('example.com')),
      );
    });

    test('maps iosbundleid URL and KPH iosBundle custom field', () {
      final credential = mapper.mapEntry(
        _entry(
          url: 'iosbundleid://Com.Example.Bank',
          customFields: const [
            VaultCustomField(
              key: 'KPH: iosBundle',
              value: 'com.example.wallet; iosbundleid://com.example.cards',
            ),
          ],
        ),
      );

      expect(credential!.url, isNull);
      expect(
        credential.serviceIdentifiers,
        containsAll(const [
          AppleAutofillV2ServiceIdentifier.bundleId('com.example.bank'),
          AppleAutofillV2ServiceIdentifier.bundleId('com.example.wallet'),
          AppleAutofillV2ServiceIdentifier.bundleId('com.example.cards'),
        ]),
      );
    });

    test('maps known custom domain and URL fields only', () {
      final credential = mapper.mapEntry(
        _entry(
          url: '',
          customFields: const [
            VaultCustomField(key: 'domain', value: 'Secure.Example.com'),
            VaultCustomField(
              key: 'KPH: URL',
              value: 'https://login.example.org/a',
            ),
            VaultCustomField(key: 'notesMirror', value: 'https://ignored.test'),
          ],
        ),
      );

      expect(
        credential!.serviceIdentifiers,
        containsAll(const [
          AppleAutofillV2ServiceIdentifier.domain('secure.example.com'),
          AppleAutofillV2ServiceIdentifier.url('https://login.example.org'),
          AppleAutofillV2ServiceIdentifier.domain('login.example.org'),
        ]),
      );
      expect(
        credential.serviceIdentifiers,
        isNot(
          contains(
            const AppleAutofillV2ServiceIdentifier.domain('ignored.test'),
          ),
        ),
      );
    });

    test('does not expose password through credential toString', () {
      final credential = mapper.mapEntry(_entry(password: 'super-secret'))!;

      expect(credential.toString(), isNot(contains('super-secret')));
      expect(credential.props.toString(), isNot(contains('super-secret')));
      expect(credential.toString(), contains('<redacted>'));
    });
  });
}

VaultEntry _entry({
  String id = 'entry-1',
  String title = 'Example',
  String username = 'alice',
  String password = 'pw',
  String url = 'https://example.com',
  List<VaultCustomField> customFields = const [],
}) {
  return VaultEntry(
    id: id,
    groupId: 'root',
    title: title,
    username: username,
    password: password,
    url: url,
    notes: 'must not be published',
    customFields: customFields,
  );
}
