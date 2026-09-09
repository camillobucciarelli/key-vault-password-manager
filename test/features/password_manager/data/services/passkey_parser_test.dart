import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/passkey_parser.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_custom_field.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_passkey.dart';

import '../../../../fixtures/passkeys/vectors.dart';

List<VaultCustomField> group(
  String pem, {
  String suffix = '',
  String credentialId = 'AQID',
  String? userHandle = 'BAUG',
  bool includeRpId = true,
  bool includeCredentialId = true,
  String? flagBe,
}) => [
  if (includeRpId)
    VaultCustomField(
      key: 'KPEX_PASSKEY_RELYING_PARTY$suffix',
      value: 'webauthn.io',
    ),
  if (includeCredentialId)
    VaultCustomField(
      key: 'KPEX_PASSKEY_CREDENTIAL_ID$suffix',
      value: credentialId,
      isProtected: true,
    ),
  if (userHandle != null)
    VaultCustomField(
      key: 'KPEX_PASSKEY_USER_HANDLE$suffix',
      value: userHandle,
      isProtected: true,
    ),
  VaultCustomField(key: 'KPEX_PASSKEY_USERNAME$suffix', value: 'alice'),
  VaultCustomField(
    key: 'KPEX_PASSKEY_PRIVATE_KEY_PEM$suffix',
    value: pem,
    isProtected: true,
  ),
  if (flagBe != null)
    VaultCustomField(key: 'KPEX_PASSKEY_FLAG_BE$suffix', value: flagBe),
];

void main() {
  const parser = PasskeyParser();

  test('parses the three algorithms', () {
    final passkeys = parser.parse([
      ...group(es256PrivateKeyPem),
      ...group(eddsaPrivateKeyPem, suffix: '_1'),
      ...group(rs256PrivateKeyPem, suffix: '_2'),
    ]);
    expect(passkeys.map((p) => p.algorithm), [
      VaultPasskeyAlgorithm.es256,
      VaultPasskeyAlgorithm.eddsa,
      VaultPasskeyAlgorithm.rs256,
    ]);
    expect(passkeys.every((p) => p.usable), isTrue);
    expect(passkeys.map((p) => p.fieldSuffix), ['', '_1', '_2']);
    final first = passkeys.first;
    expect(first.relyingPartyId, 'webauthn.io');
    expect(first.username, 'alice');
    expect(first.credentialId, [1, 2, 3]);
    expect(first.userHandle, [4, 5, 6]);
    expect(first.backupEligible, isTrue);
    expect(first.backupState, isTrue);
  });

  test('accepts padded and unpadded base64url', () {
    final raw = [250, 251, 252, 253, 254];
    final padded = base64Url.encode(raw);
    final unpadded = padded.replaceAll('=', '');
    expect(padded, isNot(unpadded));
    for (final id in [padded, unpadded]) {
      final passkey = parser
          .parse(group(es256PrivateKeyPem, credentialId: id))
          .single;
      expect(passkey.usable, isTrue);
      expect(passkey.credentialId, raw);
    }
  });

  test('truncated PEM is unusable as badKey', () {
    final passkey = parser.parse(group(truncatedPrivateKeyPem)).single;
    expect(passkey.unusableReason, VaultPasskeyUnusableReason.badKey);
    expect(passkey.relyingPartyId, 'webauthn.io');
  });

  test('missing credential id is unusable as missingField', () {
    final passkey = parser
        .parse(group(es256PrivateKeyPem, includeCredentialId: false))
        .single;
    expect(passkey.unusableReason, VaultPasskeyUnusableReason.missingField);
  });

  test('unknown OID is unusable as unsupportedAlgorithm', () {
    // A valid PKCS#8-shaped DER naming secp384r1 instead of P-256.
    final passkey = parser.parse(group(_p384PrivateKeyPem)).single;
    expect(
      passkey.unusableReason,
      VaultPasskeyUnusableReason.unsupportedAlgorithm,
    );
  });

  test('reads backup flags, defaults to true, never BS without BE', () {
    final off = parser.parse(group(es256PrivateKeyPem, flagBe: '0')).single;
    expect(off.backupEligible, isFalse);
    expect(off.backupState, isFalse, reason: 'BS must be 0 when BE is 0');
  });

  test('ignores fields outside the namespace and keeps no user handle', () {
    final passkeys = parser.parse([
      const VaultCustomField(key: 'otp', value: 'x'),
      ...group(es256PrivateKeyPem, userHandle: null),
    ]);
    expect(passkeys, hasLength(1));
    expect(passkeys.single.userHandle, isNull);
  });

  test('no passkey fields yields no passkeys', () {
    expect(
      parser.parse(const [VaultCustomField(key: 'a', value: 'b')]),
      isEmpty,
    );
  });
}

/// `openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384`, for
/// the unsupported-curve case only.
const _p384PrivateKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIG2AgEAMBAGByqGSM49AgEGBSuBBAAiBIGeMIGbAgEBBDB1+GzJoBgBHi2dbyyF
+xCPSQK/AO47poCIWfq3QejPLx65+aeX8MtSD4QTy+Djz7mhZANiAARJzLjKMKUy
hhOhy/MHTnSezOG5vUDFo54mYC6hwiqLwZ8Qyr/6brxp9kGvzvKczw5HO9OlG+HA
ED0wuzYVa8OvkoqZ0KpI76L2aqrzivFFCu1R14WbHEkWxaOtxHR5rMc=
-----END PRIVATE KEY-----
''';
