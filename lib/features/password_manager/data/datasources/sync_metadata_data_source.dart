import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/utils/portable_path.dart';
import '../../domain/models/database_sync_mapping.dart';

abstract class SyncMetadataDataSource {
  Future<DatabaseSyncMapping?> getMapping(String databasePath);
  Future<void> upsertMapping(DatabaseSyncMapping mapping);
  Future<void> removeMapping(String databasePath);
  Future<void> moveMappingPath({
    required String fromDatabasePath,
    required String toDatabasePath,
  });
  Future<List<DatabaseSyncMapping>> getAllMappings();
}

class SyncMetadataDataSourceImpl implements SyncMetadataDataSource {
  SyncMetadataDataSourceImpl();

  static const _syncSubdirectory = 'metadata';
  static const _syncFileName = 'sync_mappings.json';

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
  Future<void> moveMappingPath({
    required String fromDatabasePath,
    required String toDatabasePath,
  }) async {
    if (fromDatabasePath.trim().isEmpty || toDatabasePath.trim().isEmpty) {
      return;
    }
    if (fromDatabasePath == toDatabasePath) {
      return;
    }

    final mappings = await getAllMappings();
    final next = <DatabaseSyncMapping>[];
    for (final mapping in mappings) {
      if (mapping.databasePath == fromDatabasePath) {
        next.add(mapping.copyWith(databasePath: toDatabasePath));
      } else if (mapping.databasePath != toDatabasePath) {
        next.add(mapping);
      }
    }
    await _saveMappings(next);
  }

  @override
  Future<List<DatabaseSyncMapping>> getAllMappings() async {
    final file = await _syncMappingsFile();
    if (!await file.exists()) {
      return const [];
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return const [];
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }

    final documentsRoot = await PortablePath.documentsRoot();
    return decoded
        .whereType<Map>()
        .map((item) {
          final mapping = DatabaseSyncMapping.fromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );
          // `databasePath` doubles as the mapping key, so it is restored to an
          // absolute path here and re-encoded on save.
          return mapping.copyWith(
            databasePath: PortablePath.decode(
              mapping.databasePath,
              documentsRoot,
            ),
          );
        })
        .toList(growable: false);
  }

  Future<void> _saveMappings(List<DatabaseSyncMapping> mappings) async {
    // Resolved once, outside the loop: symlink resolution is filesystem I/O.
    final resolvedRoot = PortablePath.resolveForComparison(
      await PortablePath.documentsRoot(),
    );
    final encoded = jsonEncode(
      mappings
          .map(
            (m) => m
                .copyWith(
                  databasePath: PortablePath.encodeWithResolvedRoot(
                    m.databasePath,
                    resolvedRoot,
                  ),
                )
                .toMap(),
          )
          .toList(),
    );
    final file = await _syncMappingsFile();
    await file.writeAsString(encoded, flush: true);
  }

  Future<File> _syncMappingsFile() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, _syncSubdirectory));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(p.join(directory.path, _syncFileName));
  }
}
