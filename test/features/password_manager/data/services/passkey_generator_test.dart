// spec 023 US3 — a generated passkey is one the rest of this app can actually
// read and sign with, and one a relying party can actually verify.
//
// That round trip is the whole point of these tests: a generator that emits a
// PEM the parser rejects, or a public key that does not verify the signature
// its own private key produces, would fail only at a real sign-in on a real
// site — which is the worst possible place to find out.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/data/services/desktop_passkey_signer.dart';
import 'package:password_manager/features/password_manager/data/services/passkey_generator.dart';
import 'package:password_manager/features/password_manager/data/services/passkey_parser.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_custom_field.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_passkey.dart';
import 'package:pointycastle/export.dart';

void main() {
  // Fixed seed: these assertions are about structure, not about randomness,
  // and a fresh key on every run would make a failure hard to reproduce.
  PasskeyGenerator generator() => PasskeyGenerator(random: Random(42));

  GeneratedPasskey generate() => generator().generate(
    relyingPartyId: 'webauthn.io',
    username: 'ada@example.com',
    createdAt: DateTime(2026, 3, 4),
  );

  test('the generated key is ES256 and the parser reads it back', () {
    final created = generate();

    expect(created.passkey.algorithm, VaultPasskeyAlgorithm.es256);
    expect(created.passkey.usable, isTrue);
    expect(
      PasskeyParser.algorithmOf(created.passkey.privateKeyPem),
      VaultPasskeyAlgorithm.es256,
    );
  });

  test('a round trip through the KPEX fields preserves the credential', () {
    final created = generate();
    final fields = [
      VaultCustomField(
        key: PasskeyParser.relyingPartyKey,
        value: created.passkey.relyingPartyId,
      ),
      VaultCustomField(
        key: PasskeyParser.credentialIdKey,
        value: base64Url
            .encode(created.passkey.credentialId)
            .replaceAll('=', ''),
        isProtected: true,
      ),
      VaultCustomField(
        key: PasskeyParser.userHandleKey,
        value: base64Url
            .encode(created.passkey.userHandle!)
            .replaceAll('=', ''),
        isProtected: true,
      ),
      VaultCustomField(
        key: PasskeyParser.usernameKey,
        value: created.passkey.username,
      ),
      VaultCustomField(
        key: PasskeyParser.privateKeyPemKey,
        value: created.passkey.privateKeyPem,
        isProtected: true,
      ),
      const VaultCustomField(key: PasskeyParser.flagBeKey, value: '1'),
      const VaultCustomField(key: PasskeyParser.flagBsKey, value: '1'),
    ];

    final parsed = const PasskeyParser().parse(fields).single;
    expect(parsed.usable, isTrue);
    expect(parsed.relyingPartyId, 'webauthn.io');
    expect(parsed.username, 'ada@example.com');
    expect(parsed.credentialId, created.passkey.credentialId);
    expect(parsed.userHandle, created.passkey.userHandle);
    expect(parsed.algorithm, VaultPasskeyAlgorithm.es256);
  });

  test(
    'a signature from the new key verifies with the public key it published',
    () {
      final created = generate();

      final assertion = const DesktopPasskeySigner().sign(
        passkey: created.passkey,
        challenge: 'Y2hhbGxlbmdl',
        origin: 'https://webauthn.io',
      );

      // Exactly what the relying party verifies.
      final message = Uint8List.fromList([
        ...assertion.authenticatorData,
        ...SHA256Digest().process(assertion.clientDataJson),
      ]);
      expect(
        _verifyEs256(
          publicKeyCose: created.publicKeyCose,
          message: message,
          derSignature: assertion.signature,
        ),
        isTrue,
        reason: 'the published public key must verify its own key pair',
      );
    },
  );

  test('a tampered message does not verify', () {
    final created = generate();
    final assertion = const DesktopPasskeySigner().sign(
      passkey: created.passkey,
      challenge: 'Y2hhbGxlbmdl',
      origin: 'https://webauthn.io',
    );

    expect(
      _verifyEs256(
        publicKeyCose: created.publicKeyCose,
        message: Uint8List.fromList([1, 2, 3]),
        derSignature: assertion.signature,
      ),
      isFalse,
    );
  });

  test('the COSE key is a canonical EC2 P-256 ES256 map', () {
    final cose = generate().publicKeyCose;

    // map(5), then the five pairs in WebAuthn's canonical order. A relying
    // party that re-encodes the key to compare it byte for byte depends on it.
    expect(cose[0], 0xa5);
    expect(cose.sublist(1, 3), [0x01, 0x02]); // kty: EC2
    expect(cose.sublist(3, 5), [0x03, 0x26]); // alg: ES256
    expect(cose.sublist(5, 7), [0x20, 0x01]); // crv: P-256
    expect(cose.sublist(7, 10), [0x21, 0x58, 0x20]); // x: 32 bytes
    expect(cose.sublist(42, 45), [0x22, 0x58, 0x20]); // y: 32 bytes
    expect(cose, hasLength(77));
  });

  test('the attestation object is fmt "none" and carries the credential', () {
    final created = generate();
    final attestation = created.attestationObject;

    expect(attestation[0], 0xa3, reason: 'map(3)');
    expect(
      utf8.decode(attestation.sublist(1, 10)),
      'cfmtdnone',
      reason:
          'the CBOR text keys read as fmt/none once their headers are '
          'stripped, which this substring shows without re-decoding CBOR',
    );

    // The AT flag is what tells the site this authData carries a new
    // credential; without it registration is refused.
    final authDataStart = attestation.length - _authDataLength(created);
    final flags = attestation[authDataStart + 32];
    expect(flags & 0x40, 0x40, reason: 'AT');
    expect(flags & 0x01, 0x01, reason: 'UP');
    expect(flags & 0x04, 0x04, reason: 'UV');
    expect(flags & 0x08, 0x08, reason: 'BE');
    expect(flags & 0x10, 0x10, reason: 'BS');

    // rpIdHash is the hash of the rp id, not of the origin.
    expect(
      attestation.sublist(authDataStart, authDataStart + 32),
      SHA256Digest().process(Uint8List.fromList(utf8.encode('webauthn.io'))),
    );
  });

  test('two credentials never share a credential id', () {
    final first = generator().generate(
      relyingPartyId: 'webauthn.io',
      username: 'ada',
    );
    final second = PasskeyGenerator().generate(
      relyingPartyId: 'webauthn.io',
      username: 'ada',
    );

    expect(first.passkey.credentialId, hasLength(32));
    expect(first.passkey.credentialId, isNot(second.passkey.credentialId));
  });

  test('no description of a generated passkey carries the key', () {
    final created = generate();

    expect(created.passkey.toString(), isNot(contains('PRIVATE KEY')));
    expect(created.passkey.props.toString(), isNot(contains('PRIVATE KEY')));
  });
}

/// authData = 32 rpIdHash + 1 flags + 4 signCount + 16 aaguid + 2 length +
/// credentialId + COSE key.
int _authDataLength(GeneratedPasskey created) =>
    55 + created.passkey.credentialId.length + created.publicKeyCose.length;

/// Verifies a DER ECDSA signature against a COSE EC2 key — the relying party's
/// side of the exchange, done here so the test proves interoperability rather
/// than self-consistency.
bool _verifyEs256({
  required Uint8List publicKeyCose,
  required Uint8List message,
  required Uint8List derSignature,
}) {
  final x = publicKeyCose.sublist(10, 42);
  final y = publicKeyCose.sublist(45, 77);
  final domain = ECDomainParameters('prime256v1');
  final point = domain.curve.createPoint(_bigInt(x), _bigInt(y));
  final signature = DerNode.parse(derSignature);
  final verifier = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
    ..init(false, PublicKeyParameter<ECPublicKey>(ECPublicKey(point, domain)));
  return verifier.verifySignature(
    message,
    ECSignature(signature.children[0].bigInt, signature.children[1].bigInt),
  );
}

BigInt _bigInt(Uint8List bytes) {
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}
