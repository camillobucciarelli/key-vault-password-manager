import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/features/password_manager/domain/models/vault_passkey.dart';

void main() {
  const sentinel = 'SENTINEL-PRIVATE-KEY';
  final passkey = VaultPasskey(
    relyingPartyId: 'example.com',
    credentialId: Uint8List.fromList([1, 2, 3]),
    privateKeyPem: sentinel,
    algorithm: VaultPasskeyAlgorithm.es256,
    username: 'alice',
  );

  test('never renders the private key in props or toString', () {
    expect(passkey.props.toString(), isNot(contains(sentinel)));
    expect(passkey.toString(), isNot(contains(sentinel)));
    expect(passkey.toString(), contains('example.com'));
    expect(passkey.toString(), contains('alice'));
  });

  test('is usable only without an unusable reason', () {
    expect(passkey.usable, isTrue);
    final broken = VaultPasskey(
      relyingPartyId: 'example.com',
      credentialId: Uint8List(0),
      privateKeyPem: '',
      algorithm: VaultPasskeyAlgorithm.unknown,
      unusableReason: VaultPasskeyUnusableReason.badKey,
    );
    expect(broken.usable, isFalse);
  });

  test('equality ignores the private key value', () {
    final same = VaultPasskey(
      relyingPartyId: 'example.com',
      credentialId: Uint8List.fromList([1, 2, 3]),
      privateKeyPem: 'different',
      algorithm: VaultPasskeyAlgorithm.es256,
      username: 'alice',
    );
    expect(passkey, same);
  });
}
