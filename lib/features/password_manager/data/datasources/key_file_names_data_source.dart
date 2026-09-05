import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../core/utils/managed_storage_root.dart';
import '../../../../core/utils/mobile_file_storage.dart';
import 'metadata_cipher.dart';
import 'secure_data_source.dart';

/// spec 014 FR-3: the human-readable names of managed key files, encrypted
/// at rest like the other metadata files (FR-4) and quarantined with them
/// when the key is lost (FR-5 — `MetadataRecoveryService` scans `*.json`).
///
/// One flat map, at-rest basename → display name. Keyed by basename rather
/// than full path so an iOS container relocation does not orphan the names.
class KeyFileNamesDataSource implements ManagedKeyFileNames {
  KeyFileNamesDataSource({required SecureDataSource secureDataSource})
    : _store = EncryptedMetadataStore(secureDataSource: secureDataSource);

  final EncryptedMetadataStore _store;

  static const _fileName = 'key_file_names.json';

  @override
  Future<Map<String, String>> getAll() async {
    final raw = await _store.readString(await _file());
    if (raw == null || raw.trim().isEmpty) {
      return const {};
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return const {};
    }
    return {
      for (final entry in decoded.entries)
        if (entry.value is String) entry.key.toString(): entry.value as String,
    };
  }

  @override
  Future<void> set(String opaqueName, String displayName) async {
    final names = Map<String, String>.from(await getAll());
    names[opaqueName] = displayName;
    await _store.writeString(await _file(), jsonEncode(names));
  }

  @override
  Future<void> remove(String opaqueName) async {
    final names = Map<String, String>.from(await getAll());
    if (names.remove(opaqueName) == null) {
      return;
    }
    await _store.writeString(await _file(), jsonEncode(names));
  }

  Future<File> _file() async {
    final root = await ManagedStorageRoot.resolveDirectory();
    final directory = Directory(p.join(root.path, 'metadata'));
    await directory.create(recursive: true);
    return File(p.join(directory.path, _fileName));
  }
}
