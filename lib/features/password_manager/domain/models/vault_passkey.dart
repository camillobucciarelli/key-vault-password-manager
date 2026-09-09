import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// COSE algorithm carried by the PKCS#8 OID of the stored private key.
enum VaultPasskeyAlgorithm { es256, eddsa, rs256, unknown }

enum VaultPasskeyUnusableReason {
  missingField,
  badKey,
  unsupportedAlgorithm,
  unsupportedOnPlatform,
}

/// A WebAuthn credential stored on a vault entry in the KeePassXC
/// `KPEX_PASSKEY_*` layout (spec 023, `data-model.md`).
///
/// [privateKeyPem] is the secret: it is absent from [props] and [toString],
/// and no UI surface may render it (Constitution I).
class VaultPasskey extends Equatable {
  const VaultPasskey({
    required this.relyingPartyId,
    required this.credentialId,
    required this.privateKeyPem,
    required this.algorithm,
    this.userHandle,
    this.username = '',
    this.backupEligible = true,
    this.backupState = true,
    this.createdAt,
    this.fieldSuffix = '',
    this.unusableReason,
  });

  final String relyingPartyId;
  final Uint8List credentialId;
  final Uint8List? userHandle;
  final String username;
  final String privateKeyPem;
  final VaultPasskeyAlgorithm algorithm;
  final bool backupEligible;
  final bool backupState;
  final DateTime? createdAt;

  /// `""` for the first group, `_1`, `_2`, … for KeePassDX-style repeats.
  /// Identifies which field group a delete removes.
  final String fieldSuffix;

  final VaultPasskeyUnusableReason? unusableReason;

  bool get usable => unusableReason == null;

  @override
  List<Object?> get props => [
    relyingPartyId,
    credentialId,
    userHandle,
    username,
    algorithm,
    backupEligible,
    backupState,
    createdAt,
    fieldSuffix,
    unusableReason,
  ];

  @override
  String toString() =>
      'VaultPasskey(relyingPartyId: $relyingPartyId, username: $username, '
      'algorithm: ${algorithm.name}, usable: $usable)';
}
