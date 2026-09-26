import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/models/apple_autofill_v2_models.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_custom_field.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_entry.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_passkey.dart';
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

    test('maps androidapp URL and KPH androidPackage custom field', () {
      final credential = mapper.mapEntry(
        _entry(
          url: 'androidapp://Com.Example.Bank/path?ignored=1',
          customFields: const [
            VaultCustomField(
              key: 'KPH: androidPackage',
              value: 'com.example.wallet; androidapp://com.example.cards/path',
            ),
          ],
        ),
      );

      expect(credential!.url, isNull);
      expect(
        credential.serviceIdentifiers,
        containsAll(const [
          AppleAutofillV2ServiceIdentifier.androidPackage('com.example.bank'),
          AppleAutofillV2ServiceIdentifier.androidPackage('com.example.wallet'),
          AppleAutofillV2ServiceIdentifier.androidPackage('com.example.cards'),
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

    test('maps suffixed KPH association fields', () {
      final credential = mapper.mapEntry(
        _entry(
          url: '',
          customFields: const [
            VaultCustomField(key: 'KPH: URL 2', value: 'example.com/path'),
            VaultCustomField(key: 'KPH: iosBundle 2', value: 'com.example.ios'),
            VaultCustomField(
              key: 'KPH: androidPackage 2',
              value: 'androidapp://com.example.android/path?ignored=1',
            ),
          ],
        ),
      );

      expect(
        credential!.serviceIdentifiers,
        containsAll(const [
          AppleAutofillV2ServiceIdentifier.url('https://example.com'),
          AppleAutofillV2ServiceIdentifier.domain('example.com'),
          AppleAutofillV2ServiceIdentifier.bundleId('com.example.ios'),
          AppleAutofillV2ServiceIdentifier.androidPackage(
            'com.example.android',
          ),
        ]),
      );
    });

    test('does not expose password through credential toString', () {
      final credential = mapper.mapEntry(_entry(password: 'super-secret'))!;

      expect(credential.toString(), isNot(contains('super-secret')));
      expect(credential.props.toString(), isNot(contains('super-secret')));
      expect(credential.toString(), contains('<redacted>'));
    });

    // ---- spec 023 T301 -------------------------------------------------

    test('an entry with no passkey publishes an empty passkey list', () {
      final credential = mapper.mapEntry(_entry());

      expect(credential!.passkeys, isEmpty);
      expect(credential.toChannelMap()['passkeys'], isEmpty);
    });

    test('a usable passkey crosses the channel, unpadded and named', () {
      final credential = mapper.mapEntry(_entry(passkeys: [_passkey()]));

      final passkey = credential!.passkeys.single;
      expect(passkey.relyingPartyId, 'webauthn.io');
      expect(passkey.algorithm, 'ES256');
      expect(passkey.credentialId, 'AQIDBAU');
      expect(passkey.userHandle, 'CQk');
      expect(passkey.privateKeyPem, _pem);

      final map = credential.toChannelMap()['passkeys'] as List;
      expect((map.single as Map)['rpId'], 'webauthn.io');
      expect((map.single as Map)['be'], isTrue);
    });

    test('a passkey with no username of its own borrows the entry\'s', () {
      final credential = mapper.mapEntry(
        _entry(
          username: 'alice',
          passkeys: [_passkey(username: '  ')],
        ),
      );

      expect(credential!.passkeys.single.username, 'alice');
    });

    test('an unusable passkey is not sealed', () {
      final credential = mapper.mapEntry(
        _entry(
          passkeys: [
            _passkey(unusableReason: VaultPasskeyUnusableReason.badKey),
          ],
        ),
      );

      expect(credential!.passkeys, isEmpty);
    });

    // FR-013: the entry has nothing to fill but something to sign with.
    test('an entry with a passkey and no password is still published', () {
      final credential = mapper.mapEntry(
        _entry(password: '', passkeys: [_passkey()]),
      );

      expect(credential, isNotNull);
      expect(credential!.password, isEmpty);
      expect(credential.passkeys, hasLength(1));
    });

    test('an entry with neither a password nor a passkey is skipped', () {
      expect(mapper.mapEntry(_entry(password: '')), isNull);
    });

    test('no description of the payload carries the key', () {
      final credential = mapper.mapEntry(_entry(passkeys: [_passkey()]))!;

      expect(credential.toString(), isNot(contains('PRIVATE KEY')));
      expect(credential.passkeys.single.toString(), isNot(contains('fakeZ')));
      expect(
        credential.passkeys.single.toString(),
        isNot(contains('PRIVATE KEY')),
      );
      expect(credential.props.toString(), isNot(contains('PRIVATE KEY')));
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
  List<VaultPasskey> passkeys = const [],
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
    passkeys: passkeys,
  );
}

/// Not a real key: the tests assert it never reaches a description, so it
/// only has to look like one.
const _pem = '-----BEGIN PRIVATE KEY-----\nZmFrZQ==\n-----END PRIVATE KEY-----';

VaultPasskey _passkey({
  String relyingPartyId = 'webauthn.io',
  String username = 'ada',
  VaultPasskeyAlgorithm algorithm = VaultPasskeyAlgorithm.es256,
  VaultPasskeyUnusableReason? unusableReason,
}) => VaultPasskey(
  relyingPartyId: relyingPartyId,
  // Three bytes so base64url needs one '=' of padding, which must be gone.
  credentialId: Uint8List.fromList([1, 2, 3, 4, 5]),
  userHandle: Uint8List.fromList([9, 9]),
  username: username,
  privateKeyPem: _pem,
  algorithm: algorithm,
  unusableReason: unusableReason,
);
