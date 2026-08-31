import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/pointycastle.dart'
    show AEADParameters, KeyParameter;

import 'secure_data_source.dart';

/// AES-256-GCM seal/open for the spec 014 FR-4 metadata files.
///
/// File shape: one version byte, a random 12-byte nonce, then the ciphertext
/// with the 16-byte GCM tag appended. GCM rather than CBC because these
/// files are decrypted on every start and a tampered ciphertext must fail
/// loudly instead of yielding garbage the JSON decoder half-parses.
///
/// No key material ever enters `toString`, logs or diagnostic state.
class MetadataCipher {
  const MetadataCipher._();

  static const _version = 0x01;
  static const _nonceLength = 12;
  static const _macBits = 128;

  static Uint8List seal(Uint8List key, Uint8List plaintext) {
    final nonce = _randomNonce();
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), _macBits, nonce, Uint8List(0)),
      );
    final ciphertext = cipher.process(plaintext);
    final out = Uint8List(1 + _nonceLength + ciphertext.length);
    out[0] = _version;
    out.setRange(1, 1 + _nonceLength, nonce);
    out.setRange(1 + _nonceLength, out.length, ciphertext);
    return out;
  }

  /// Throws [FormatException] on an unknown version and
  /// `InvalidCipherTextException` on a tampered payload.
  static Uint8List open(Uint8List key, Uint8List sealed) {
    if (sealed.isEmpty || sealed[0] != _version) {
      throw const FormatException('unknown metadata cipher version');
    }
    if (sealed.length < 1 + _nonceLength + _macBits ~/ 8) {
      throw const FormatException('sealed metadata payload too short');
    }
    final nonce = sealed.sublist(1, 1 + _nonceLength);
    final ciphertext = sealed.sublist(1 + _nonceLength);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(KeyParameter(key), _macBits, nonce, Uint8List(0)),
      );
    return cipher.process(ciphertext);
  }

  static Uint8List _randomNonce() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(_nonceLength, (_) => random.nextInt(256)),
    );
  }
}

/// Reads and writes one metadata file encrypted at rest (spec 014 FR-4/FR-5).
///
/// Key policy, enforced here so all four call sites share it:
/// - the key lives in the platform secure store, created once;
/// - an absent key with ciphertext present is the FR-5 state — the content
///   reads as empty and the key is NEVER minted over existing ciphertext,
///   which would silently destroy it;
/// - an unavailable secure store also reads as empty and blocks every write;
/// - no code path ever writes a plaintext metadata file.
class EncryptedMetadataStore {
  EncryptedMetadataStore({required this.secureDataSource});

  final SecureDataSource secureDataSource;

  /// Decrypted content of [file], or `null` for "no readable content": file
  /// absent, secure store unavailable, key absent, or tampered bytes.
  Future<String?> readString(File file) async {
    if (!await file.exists()) {
      return null;
    }
    final Uint8List key;
    try {
      final encoded = await secureDataSource.readMetadataKey();
      if (encoded == null) {
        // FR-5: ciphertext without a key is a defined empty state, never a
        // reason to mint a new key.
        return null;
      }
      key = base64Decode(encoded);
    } catch (_) {
      return null;
    }
    try {
      return utf8.decode(MetadataCipher.open(key, await file.readAsBytes()));
    } catch (_) {
      // Tampered or truncated ciphertext fails loudly at the cipher and
      // reads as empty here; it is never half-parsed.
      return null;
    }
  }

  /// Encrypts [content] into [file]. Throws [StateError] when no key can be
  /// used — the write is refused rather than falling back to plaintext.
  Future<void> writeString(File file, String content) async {
    final String encoded;
    try {
      final existing = await secureDataSource.readMetadataKey();
      if (existing != null) {
        encoded = existing;
      } else if (await file.exists()) {
        // FR-5 / safety gate 4: never regenerate the key over existing
        // ciphertext.
        throw StateError(
          'metadata key unavailable for existing ciphertext; refusing to '
          'mint a new key over it',
        );
      } else {
        encoded = await secureDataSource.createMetadataKey();
      }
    } on StateError {
      rethrow;
    } catch (error) {
      throw StateError('secure store unavailable; refusing plaintext write');
    }
    final sealed = MetadataCipher.seal(
      base64Decode(encoded),
      Uint8List.fromList(utf8.encode(content)),
    );
    await file.writeAsBytes(sealed, flush: true);
  }
}
