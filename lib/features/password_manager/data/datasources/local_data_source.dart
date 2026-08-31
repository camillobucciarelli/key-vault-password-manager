import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import '../../../../core/utils/managed_storage_root.dart';
import 'metadata_cipher.dart';
import 'secure_data_source.dart';

abstract class LocalDataSource {
  Future<bool> getAutofillPromptSeen();
  Future<void> setAutofillPromptSeen(bool seen);
}

class LocalDataSourceImpl implements LocalDataSource {
  static const autofillPromptSeenKey = 'autofillPromptSeen';
  static const _localStateSubdirectory = 'metadata';
  static const _localStateFileName = 'local_state.json';

  LocalDataSourceImpl({required SecureDataSource secureDataSource})
    : _store = EncryptedMetadataStore(secureDataSource: secureDataSource);

  final EncryptedMetadataStore _store;

  @override
  Future<bool> getAutofillPromptSeen() async {
    final data = await _readState();
    return data[autofillPromptSeenKey] as bool? ?? false;
  }

  @override
  Future<void> setAutofillPromptSeen(bool seen) async {
    final data = await _readState();
    data[autofillPromptSeenKey] = seen;
    await _writeState(data);
  }

  Future<Map<String, dynamic>> _readState() async {
    final file = await _stateFile();
    final raw = await _store.readString(file);
    if (raw == null || raw.trim().isEmpty) {
      return <String, dynamic>{};
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return <String, dynamic>{};
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<void> _writeState(Map<String, dynamic> state) async {
    final file = await _stateFile();
    await _store.writeString(file, jsonEncode(state));
  }

  Future<File> _stateFile() async {
    final root = await ManagedStorageRoot.resolveDirectory();
    final directory = Directory(p.join(root.path, _localStateSubdirectory));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(p.join(directory.path, _localStateFileName));
  }
}
