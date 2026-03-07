import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/database_sync_mapping.dart';

abstract class SyncMetadataDataSource {
  Future<DatabaseSyncMapping?> getMapping(String databasePath);
  Future<void> upsertMapping(DatabaseSyncMapping mapping);
  Future<void> removeMapping(String databasePath);
  Future<List<DatabaseSyncMapping>> getAllMappings();
}

class SyncMetadataDataSourceImpl implements SyncMetadataDataSource {
  SyncMetadataDataSourceImpl({required this.sharedPreferences});

  static const _syncMappingsKey = 'SYNC_MAPPINGS';

  final SharedPreferences sharedPreferences;

  @override
  Future<DatabaseSyncMapping?> getMapping(String databasePath) async {
    final mappings = await getAllMappings();
    for (final mapping in mappings) {
      if (mapping.databasePath == databasePath) {
        return mapping;
      }
    }
    return null;
  }

  @override
  Future<void> upsertMapping(DatabaseSyncMapping mapping) async {
    final mappings = await getAllMappings();
    final next = <DatabaseSyncMapping>[];
    var updated = false;
    for (final item in mappings) {
      if (item.databasePath == mapping.databasePath) {
        next.add(mapping);
        updated = true;
      } else {
        next.add(item);
      }
    }
    if (!updated) {
      next.add(mapping);
    }

    await _saveMappings(next);
  }

  @override
  Future<void> removeMapping(String databasePath) async {
    final mappings = await getAllMappings();
    final next = mappings
        .where((mapping) => mapping.databasePath != databasePath)
        .toList(growable: false);
    await _saveMappings(next);
  }

  @override
  Future<List<DatabaseSyncMapping>> getAllMappings() async {
    final raw = sharedPreferences.getString(_syncMappingsKey);
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }

    return decoded
        .whereType<Map>()
        .map(
          (item) => DatabaseSyncMapping.fromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false);
  }

  Future<void> _saveMappings(List<DatabaseSyncMapping> mappings) {
    final encoded = jsonEncode(mappings.map((m) => m.toMap()).toList());
    return sharedPreferences.setString(_syncMappingsKey, encoded);
  }
}
