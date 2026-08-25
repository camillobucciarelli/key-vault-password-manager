import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:loggy/loggy.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/portable_path.dart';
import '../../domain/entities/database_record.dart';
import '../../domain/repositories/database_registry_repository.dart';

/// One-time bridge from the pre-registry SharedPreferences path keys
/// (`CACHED_DATABASE_PATH` / `RECENT_DATABASE_PATHS`) to the registry.
///
/// Contract (P1-3):
/// * A durable `migrationCompletedKey` marker makes every call after the
///   first a no-op, regardless of what legacy cleanup did or did not
///   finish.
/// * If the registry is already non-empty when this runs (any reason —
///   restore, a different startup path, a previous partial run that
///   committed records but crashed before the marker), it is authoritative:
///   legacy data is neither imported nor used to change the active id. The
///   marker is written and legacy keys are best-effort cleaned up, but nothing
///   already in the registry is touched.
/// * If the registry is empty, the whole migration (every inserted record +
///   the active id) is one unit: any failure — including the marker write
///   itself — rolls everything back to the empty-registry/previous-active
///   snapshot and leaves the legacy SharedPreferences keys untouched, so a
///   later app start retries from scratch.
/// * Legacy key cleanup runs only after the marker is durable, and its own
///   failure is logged and swallowed — the marker (not "did cleanup run")
///   is what stops re-import.
class LegacyDatabaseRegistryMigration {
  LegacyDatabaseRegistryMigration({
    required this.sharedPreferences,
    required this.registryRepository,
    Future<bool> Function(String key, bool value)? setBool,
    Future<bool> Function(String key)? removePreference,
  }) : _setBool = setBool,
       _removePreference = removePreference;

  static const cachedDatabasePathKey = 'CACHED_DATABASE_PATH';
  static const recentDatabasePathsKey = 'RECENT_DATABASE_PATHS';

  /// Namespaced so it can never collide with a legacy key of the same
  /// shape, and versioned so a future migration generation can distinguish
  /// "never ran" from "ran an earlier version".
  static const migrationCompletedKey =
      'password_manager.database_registry.legacy_migration.v1.completed';

  final SharedPreferences sharedPreferences;
  final DatabaseRegistryRepository registryRepository;

  /// Test seams only: production always goes through
  /// [SharedPreferences.setBool]/[SharedPreferences.remove]. `Future<bool>`
  /// return value is honored the same way `SharedPreferences` itself
  /// documents it — `false` means the write did not happen.
  final Future<bool> Function(String key, bool value)? _setBool;
  final Future<bool> Function(String key)? _removePreference;

  Future<void> migrate() async {
    if (sharedPreferences.getBool(migrationCompletedKey) == true) {
      return;
    }

    final existingRecords = await registryRepository.list();
    if (existingRecords.isNotEmpty) {
      // Authoritative registry: never import, never touch active id.
      await _markCompleted();
      await _cleanupLegacyPreferences();
      return;
    }

    final cachedPath = _normalize(
      sharedPreferences.getString(cachedDatabasePathKey),
    );
    final recentPaths =
        sharedPreferences.getStringList(recentDatabasePathsKey) ?? const [];
    if (cachedPath == null && recentPaths.isEmpty) {
      await _markCompleted();
      return;
    }

    final previousActiveId = await registryRepository.getActive();
    final records = <DatabaseRecord>[];
    final insertedIds = <String>[];
    DatabaseRecord? activeRecord;
    try {
      final paths = <String>[...recentPaths, ?cachedPath];
      for (final rawPath in paths) {
        final normalized = _normalize(rawPath);
        if (normalized == null) {
          continue;
        }

        final canonicalPath = _canonicalPath(normalized);
        var record = _findByPath(records, canonicalPath);
        if (record == null) {
          final now = DateTime.now();
          record = DatabaseRecord(
            databaseId: _generateDatabaseId(),
            canonicalPath: canonicalPath,
            displayName: p.basename(canonicalPath),
            sourceType: DatabaseSourceType.local,
            fileHash: await _hashIfPresent(canonicalPath),
            createdAt: now,
            updatedAt: now,
          );
          await registryRepository.upsert(record);
          insertedIds.add(record.databaseId);
          records.add(record);
        }

        if (cachedPath != null && _samePath(normalized, cachedPath)) {
          activeRecord = record;
        }
      }

      if (activeRecord != null) {
        await registryRepository.setActive(activeRecord.databaseId);
      }
      // The marker write is inside the try block deliberately: if it fails,
      // the registry writes above must roll back too — a migration that
      // "completed" in the registry but never got a durable marker would
      // re-run and duplicate records on the next launch.
      await _markCompleted();
    } catch (_) {
      await _rollback(
        insertedIds: insertedIds,
        previousActiveId: previousActiveId,
      );
      rethrow;
    }

    await _cleanupLegacyPreferences();
  }

  Future<void> _markCompleted() async {
    final saved = await (_setBool ?? sharedPreferences.setBool)(
      migrationCompletedKey,
      true,
    );
    if (!saved) {
      throw StateError('Unable to persist legacy registry migration marker.');
    }
  }

  Future<void> _rollback({
    required List<String> insertedIds,
    required String? previousActiveId,
  }) async {
    Object? rollbackError;
    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        rollbackError ??= error;
      }
    }

    await attempt(() async {
      final removed = await (_removePreference ?? sharedPreferences.remove)(
        migrationCompletedKey,
      );
      if (!removed && sharedPreferences.containsKey(migrationCompletedKey)) {
        throw StateError('Unable to roll back the migration marker.');
      }
    });
    for (final databaseId in insertedIds.reversed) {
      await attempt(() => registryRepository.remove(databaseId));
    }
    await attempt(() => registryRepository.setActive(previousActiveId));
    if (rollbackError != null) {
      throw StateError('Legacy registry migration rollback failed.');
    }
  }

  Future<void> _cleanupLegacyPreferences() async {
    for (final key in [recentDatabasePathsKey, cachedDatabasePathKey]) {
      try {
        await (_removePreference ?? sharedPreferences.remove)(key);
      } catch (error, stackTrace) {
        // The marker is already durable at this point — a cleanup failure
        // must not (and, by the marker check at the top of `migrate`,
        // cannot) trigger a re-import on the next launch.
        logWarning(
          'Unable to remove a legacy database preference after migration.',
          error,
          stackTrace,
        );
      }
    }
  }

  DatabaseRecord? _findByPath(List<DatabaseRecord> records, String path) {
    for (final record in records) {
      if (_samePath(record.canonicalPath, path)) {
        return record;
      }
    }
    return null;
  }

  bool _samePath(String left, String right) {
    final canonicalLeft = _canonicalPath(left);
    final canonicalRight = _canonicalPath(right);
    if (p.equals(canonicalLeft, canonicalRight)) {
      return true;
    }
    try {
      return FileSystemEntity.identicalSync(canonicalLeft, canonicalRight);
    } on FileSystemException {
      return false;
    }
  }

  String _canonicalPath(String path) =>
      PortablePath.resolveForComparison(p.normalize(p.absolute(path)));

  Future<String?> _hashIfPresent(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }
    return md5.convert(await file.readAsBytes()).toString();
  }

  String _generateDatabaseId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final random = Random.secure().nextInt(1 << 32).toRadixString(16);
    return 'db_$now$random';
  }

  String? _normalize(String? path) {
    final normalized = path?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
