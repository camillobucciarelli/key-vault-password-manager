import 'dart:convert';
import 'dart:typed_data';

import '../../domain/models/vault_custom_field.dart';
import '../../domain/models/vault_passkey.dart';

/// Spec 023 T012 — reads KeePassXC `KPEX_PASSKEY_*` fields into
/// [VaultPasskey]s. Pure, never throws: anything it cannot interpret becomes
/// an unusable passkey so the fields are shown, never dropped (FR-012).
class PasskeyParser {
  const PasskeyParser();

  static const keyPrefix = 'KPEX_PASSKEY_';
  static const relyingPartyKey = '${keyPrefix}RELYING_PARTY';
  static const credentialIdKey = '${keyPrefix}CREDENTIAL_ID';
  static const userHandleKey = '${keyPrefix}USER_HANDLE';
  static const usernameKey = '${keyPrefix}USERNAME';
  static const privateKeyPemKey = '${keyPrefix}PRIVATE_KEY_PEM';
  static const flagBeKey = '${keyPrefix}FLAG_BE';
  static const flagBsKey = '${keyPrefix}FLAG_BS';

  static bool isPasskeyKey(String key) => key.startsWith(keyPrefix);

  static final _suffix = RegExp(r'^(.*?)(_\d+)?$');

  List<VaultPasskey> parse(
    List<VaultCustomField> fields, {
    DateTime? createdAt,
  }) {
    final groups = <String, Map<String, String>>{};
    for (final field in fields) {
      if (!isPasskeyKey(field.key)) continue;
      final match = _suffix.firstMatch(field.key)!;
      final suffix = match.group(2) ?? '';
      groups.putIfAbsent(suffix, () => {})[match.group(1)!] = field.value;
    }
    return [
      for (final entry in groups.entries)
        _parseGroup(entry.key, entry.value, createdAt),
    ];
  }

  VaultPasskey _parseGroup(
    String suffix,
    Map<String, String> group,
    DateTime? createdAt,
  ) {
    final rpId = group[relyingPartyKey];
    final credentialId = group[credentialIdKey];
    final pem = group[privateKeyPemKey];
    var reason = (rpId == null || credentialId == null || pem == null)
        ? VaultPasskeyUnusableReason.missingField
        : null;

    var credentialBytes = Uint8List(0);
    Uint8List? userHandle;
    if (reason == null) {
      try {
        credentialBytes = decodeBase64Url(credentialId!);
        final handle = group[userHandleKey];
        userHandle = handle == null ? null : decodeBase64Url(handle);
      } on FormatException {
        reason = VaultPasskeyUnusableReason.badKey;
      }
    }

    var algorithm = VaultPasskeyAlgorithm.unknown;
    if (reason == null) {
      algorithm = algorithmOf(pem!);
      if (algorithm == VaultPasskeyAlgorithm.unknown) {
        reason = _pemParses(pem)
            ? VaultPasskeyUnusableReason.unsupportedAlgorithm
            : VaultPasskeyUnusableReason.badKey;
      }
    }

    // WebAuthn forbids BS without BE; a record saying BE=0 with BS absent
    // would otherwise sign 0x10 alone and get rejected by the relying party.
    final backupEligible = group[flagBeKey] != '0';
    return VaultPasskey(
      relyingPartyId: rpId ?? '',
      credentialId: credentialBytes,
      userHandle: userHandle,
      username: group[usernameKey] ?? '',
      privateKeyPem: pem ?? '',
      algorithm: algorithm,
      backupEligible: backupEligible,
      backupState: backupEligible && group[flagBsKey] != '0',
      createdAt: createdAt,
      fieldSuffix: suffix,
      unusableReason: reason,
    );
  }

  /// Accepts padded and unpadded base64url (KeePassXC omits padding).
  static Uint8List decodeBase64Url(String value) =>
      base64Url.decode(base64Url.normalize(value.trim()));

  static const _oidEc = '1.2.840.10045.2.1';
  static const _oidP256 = '1.2.840.10045.3.1.7';
  static const _oidEd25519 = '1.3.101.112';
  static const _oidRsa = '1.2.840.113549.1.1.1';

  /// The algorithm named by the PKCS#8 `AlgorithmIdentifier`, or `unknown`
  /// when the PEM does not parse or names something else.
  static VaultPasskeyAlgorithm algorithmOf(String pem) {
    final info = _privateKeyInfo(pem);
    if (info == null) return VaultPasskeyAlgorithm.unknown;
    final algorithm = info.children[1];
    final oid = algorithm.children.isEmpty ? null : algorithm.children[0].oid;
    switch (oid) {
      case _oidEc:
        final params = algorithm.children.length > 1
            ? algorithm.children[1].oid
            : null;
        return params == _oidP256
            ? VaultPasskeyAlgorithm.es256
            : VaultPasskeyAlgorithm.unknown;
      case _oidEd25519:
        return VaultPasskeyAlgorithm.eddsa;
      case _oidRsa:
        return VaultPasskeyAlgorithm.rs256;
      default:
        return VaultPasskeyAlgorithm.unknown;
    }
  }

  static bool _pemParses(String pem) => _privateKeyInfo(pem) != null;

  /// `PrivateKeyInfo ::= SEQUENCE { version, algorithm, privateKey, ... }`.
  static DerNode? _privateKeyInfo(String pem) {
    final der = pemToDer(pem);
    if (der == null) return null;
    try {
      final root = DerNode.parse(der);
      if (root.tag != DerNode.sequence || root.children.length < 3) {
        return null;
      }
      return root;
    } on FormatException {
      return null;
    }
  }

  /// Returns null when the text is not a single PEM block.
  static Uint8List? pemToDer(String pem) {
    final lines = LineSplitter.split(
      pem,
    ).map((line) => line.trim()).where((line) => line.isNotEmpty).toList();
    if (lines.length < 3 ||
        !lines.first.startsWith('-----BEGIN ') ||
        !lines.last.startsWith('-----END ')) {
      return null;
    }
    try {
      return base64.decode(lines.sublist(1, lines.length - 1).join());
    } on FormatException {
      return null;
    }
  }
}

/// Minimal DER reader: enough to walk PKCS#8, ECPrivateKey, RSAPrivateKey
/// and SubjectPublicKeyInfo. Constructed types are parsed eagerly; primitives
/// keep their raw [content].
class DerNode {
  DerNode._(this.tag, this.content, this.children);

  static const sequence = 0x30;
  static const integer = 0x02;
  static const bitString = 0x03;
  static const octetString = 0x04;
  static const objectIdentifier = 0x06;

  final int tag;
  final Uint8List content;
  final List<DerNode> children;

  static DerNode parse(Uint8List bytes) {
    final (node, end) = _read(bytes, 0);
    if (end != bytes.length) throw const FormatException('trailing bytes');
    return node;
  }

  static List<DerNode> parseAll(Uint8List bytes) {
    final nodes = <DerNode>[];
    var offset = 0;
    while (offset < bytes.length) {
      final (node, end) = _read(bytes, offset);
      nodes.add(node);
      offset = end;
    }
    return nodes;
  }

  static (DerNode, int) _read(Uint8List bytes, int offset) {
    if (offset + 2 > bytes.length) throw const FormatException('short');
    final tag = bytes[offset];
    var length = bytes[offset + 1];
    var cursor = offset + 2;
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      if (count == 0 || count > 4 || cursor + count > bytes.length) {
        throw const FormatException('bad length');
      }
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | bytes[cursor + i];
      }
      cursor += count;
    }
    if (cursor + length > bytes.length) throw const FormatException('short');
    final content = Uint8List.sublistView(bytes, cursor, cursor + length);
    final constructed = tag & 0x20 != 0;
    return (
      DerNode._(tag, content, constructed ? parseAll(content) : const []),
      cursor + length,
    );
  }

  String? get oid {
    if (tag != objectIdentifier || content.isEmpty) return null;
    final parts = <int>[content[0] ~/ 40, content[0] % 40];
    var value = 0;
    for (final byte in content.skip(1)) {
      value = (value << 7) | (byte & 0x7f);
      if (byte & 0x80 == 0) {
        parts.add(value);
        value = 0;
      }
    }
    return parts.join('.');
  }

  BigInt get bigInt {
    var value = BigInt.zero;
    for (final byte in content) {
      value = (value << 8) | BigInt.from(byte);
    }
    return value;
  }

  /// BIT STRING payload without the leading unused-bits byte.
  Uint8List get bitStringBytes =>
      content.isEmpty ? content : Uint8List.sublistView(content, 1);
}
