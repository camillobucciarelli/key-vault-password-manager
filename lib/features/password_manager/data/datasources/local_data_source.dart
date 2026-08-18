import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/utils/portable_path.dart';

abstract class LocalDataSource {
  Future<String?> getCachedKeyFilePath();
  Future<void> cacheKeyFilePath(String? path);
  Future<bool> getAutofillPromptSeen();
  Future<void> setAutofillPromptSeen(bool seen);
}

class LocalDataSourceImpl implements LocalDataSource {
  static const keyFilePathKey = 'cachedKeyFilePath';
  static const autofillPromptSeenKey = 'autofillPromptSeen';
  static const _localStateSubdirectory = 'metadata';
  static const _localStateFileName = 'local_state.json';

  LocalDataSourceImpl();

  @override
  Future<String?> getCachedKeyFilePath() async {
    final data = await _readState();
    final value = data[keyFilePathKey] as String?;
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    // Unlock-time fallback when no security profile exists, so it has to
    // survive an app-container relocation just like the profile's keyFilePath.
    return PortablePath.decode(value, await PortablePath.documentsRoot());
  }

  @override
  Future<void> cacheKeyFilePath(String? path) async {
    final data = await _readState();
    if (path == null || path.trim().isEmpty) {
      data.remove(keyFilePathKey);
      await _writeState(data);
      return;
    }
    data[keyFilePathKey] = PortablePath.encode(
      path,
      await PortablePath.documentsRoot(),
    );
    await _writeState(data);
  }

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
    if (!await file.exists()) {
      return <String, dynamic>{};
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
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
    await file.writeAsString(jsonEncode(state), flush: true);
  }

  Future<File> _stateFile() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, _localStateSubdirectory));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(p.join(directory.path, _localStateFileName));
  }
}
