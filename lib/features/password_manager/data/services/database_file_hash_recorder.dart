import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:loggy/loggy.dart';
import 'package:path/path.dart' as p;

import '../../../../core/utils/portable_path.dart';
import '../../domain/entities/database_record.dart';
import '../../domain/repositories/database_registry_repository.dart';

/// Token returned by [DatabaseFileHashRecorder.beginWrite]: the registry
/// record matched by canonical path (if any) BEFORE its `fileHash` was
/// invalidated, so a failed write can restore it exactly.
class DatabaseFileHashWrite {
  const DatabaseFileHashWrite({
    required this.databasePath,
    required this.recordBefore,
  });

  final String databasePath;
  final DatabaseRecord? recordBefore;
}

/// Keeps registry content identity aligned with KDBX replacements.
///
/// Protocol (never "swallow and keep the old hash"):
/// 1. `beginWrite` invalidates (clears) the matching record's `fileHash`
///    BEFORE the durable write starts. A record with no stored hash is
///    documented as "no hash to compare" — never a stale one.
/// 2. On write success, `completeWrite` computes and records the new hash.
///    A failure here (e.g. registry unavailable) leaves the hash absent,
///    never restores the old one — the durable write already happened and
///    the old hash no longer describes the file on disk.
/// 3. On write failure, `rollbackWrite` restores the pre-write record
///    (including its old hash), because the file on disk is unchanged.
class DatabaseFileHashRecorder {
  DatabaseFileHashRecorder({required this.registryRepository});

  final DatabaseRegistryRepository registryRepository;

  Future<DatabaseFileHashWrite> beginWrite(String databasePath) async {
    final record = await _findByPath(databasePath);
    if (record != null) {
      await registryRepository.upsert(
        record.copyWith(clearFileHash: true, updatedAt: DateTime.now()),
      );
    }
    return DatabaseFileHashWrite(
      databasePath: databasePath,
      recordBefore: record,
    );
  }

  /// Runs [write] wrapped in the invalidate/complete/rollback protocol.
  /// If invalidation itself fails, [write] never starts (the failure
  /// propagates from `beginWrite`, called before this).
  Future<T> trackWrite<T>({
    required String databasePath,
    required Uint8List bytes,
    required Future<T> Function() write,
  }) async {
    final transaction = await beginWrite(databasePath);
    try {
      final result = await write();
      await completeWrite(transaction, bytes);
      return result;
    } catch (error, stackTrace) {
      await rollbackWrite(transaction);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> completeWrite(
    DatabaseFileHashWrite transaction,
    Uint8List bytes,
  ) async {
    final record = transaction.recordBefore;
    if (record == null) {
      return;
    }
    try {
      // Re-read by id: `beginWrite` already invalidated this record, so the
      // authoritative current state (not the pre-write snapshot) is what a
      // refresh must build on.
      final current = await registryRepository.getById(record.databaseId);
      if (current == null) {
        return;
      }
      await registryRepository.upsert(
        current.copyWith(
          fileHash: md5.convert(bytes).toString(),
          updatedAt: DateTime.now(),
        ),
      );
    } catch (error, stackTrace) {
      // The durable write already succeeded. A refresh failure here must
      // leave the hash ABSENT (already cleared by beginWrite) rather than
      // restore a hash that no longer matches the file on disk.
      logWarning(
        'Unable to refresh the database registry hash after a durable '
        'write; the hash is left absent rather than stale.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> rollbackWrite(DatabaseFileHashWrite transaction) async {
    final record = transaction.recordBefore;
    if (record == null) {
      return;
    }
    try {
      await registryRepository.upsert(record);
    } catch (error, stackTrace) {
      logWarning(
        'Unable to restore the database registry hash after a failed '
        'write.',
        error,
        stackTrace,
      );
    }
  }

  /// Startup reconciliation: fills in a missing `fileHash` for any record
  /// whose canonical file still exists. Cheap (one read per record) and
  /// best-effort — a failure here must not block startup.
  Future<void> reconcileMissingHashes() async {
    List<DatabaseRecord> records;
    try {
      records = await registryRepository.list();
    } catch (error, stackTrace) {
      // A corrupt/unreadable registry must not block startup either — the
      // per-record loop below already treats every failure this way, but
      // the `list()` call that feeds it was unprotected.
      logWarning(
        'Unable to list the database registry for hash reconciliation at '
        'startup.',
        error,
        stackTrace,
      );
      return;
    }

    for (final record in records) {
      if (record.fileHash != null) {
        continue;
      }
      try {
        final file = File(record.canonicalPath);
        if (!await file.exists()) {
          continue;
        }
        await registryRepository.upsert(
          record.copyWith(
            fileHash: md5.convert(await file.readAsBytes()).toString(),
            updatedAt: DateTime.now(),
          ),
        );
      } catch (error, stackTrace) {
        logWarning(
          'Unable to reconcile a missing database registry hash at '
          'startup.',
          error,
          stackTrace,
        );
      }
    }
  }

  Future<DatabaseRecord?> _findByPath(String databasePath) async {
    final resolvedPath = PortablePath.resolveForComparison(databasePath);
    for (final record in await registryRepository.list()) {
      final resolvedRecordPath = PortablePath.resolveForComparison(
        record.canonicalPath,
      );
      if (p.equals(resolvedRecordPath, resolvedPath)) {
        return record;
      }
    }
    return null;
  }
}
