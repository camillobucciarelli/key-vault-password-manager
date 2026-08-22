import 'dart:io';

import '../../domain/repositories/database_sync_repository.dart';
import 'database_path_mutex.dart';

/// Atomic database rename — spec 008 Gate 1 T106.
///
/// Locks the old and the new canonical path in a single
/// [DatabasePathMutex.withDatabaseLock] acquisition (the mutex deduplicates
/// and sorts, so inverse concurrent renames A→B / B→A are deadlock-free) and,
/// while holding both, renames the file and moves the sync mapping. If the
/// mapping move fails the file rename is rolled back before rethrowing, so no
/// other writer can ever observe a renamed file whose mapping still points at
/// the old path.
///
/// Registry/security profile updates deliberately stay with the caller
/// (`VaultSessionCoordinator.updateDatabaseSettings`): they are
/// SharedPreferences state, not database-file writes — the frozen writer
/// inventory forbids taking the database mutex for them — and the
/// coordinator's existing rollback already restores them on failure.
///
/// The file operations here are intentionally direct `dart:io` calls, NOT
/// `DatabaseFileRepository.renameFile`: that port method takes the same lock
/// itself, and the mutex is not reentrant (T105 anti-nesting audit).
class DatabaseRenameTransaction {
  DatabaseRenameTransaction({
    required DatabasePathMutex mutex,
    required DatabaseSyncRepository syncRepository,
  }) : _mutex = mutex,
       _syncRepository = syncRepository;

  final DatabasePathMutex _mutex;
  final DatabaseSyncRepository _syncRepository;

  /// Renames [sourcePath] to [targetPath] and moves the sync mapping with it,
  /// atomically with respect to every other database writer on either path.
  Future<void> renameDatabase({
    required String sourcePath,
    required String targetPath,
  }) {
    return _mutex.withDatabaseLock([sourcePath, targetPath], () async {
      await File(sourcePath).rename(targetPath);
      try {
        await _syncRepository.moveMappingPath(
          fromDatabasePath: sourcePath,
          toDatabasePath: targetPath,
        );
      } catch (_) {
        await File(targetPath).rename(sourcePath);
        rethrow;
      }
    });
  }
}
