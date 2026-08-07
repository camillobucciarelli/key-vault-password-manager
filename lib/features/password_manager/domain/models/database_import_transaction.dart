import 'database_import_result.dart';

/// Staged import/commit value types for the [DatabaseFileRepository]
/// transaction flow (duplicate detection, commit, rollback). Moved out of
/// `data/services/database_import_service.dart` so the coordinator can depend
/// on the domain port instead of the concrete data service (C-7).
class StagedDatabaseImport {
  const StagedDatabaseImport({
    required this.imported,
    required this.preferredFileName,
  });

  final DatabaseImportResult imported;
  final String preferredFileName;
}

/// Result of committing a [StagedDatabaseImport] to its final location.
/// `backupPath`, when present, must be kept until
/// [DatabaseFileRepository.finalizeDatabaseCommit] succeeds, and restored by
/// [DatabaseFileRepository.rollbackDatabaseCommit] on failure.
class DatabaseFileCommit {
  const DatabaseFileCommit({required this.databasePath, this.backupPath});

  final String databasePath;
  final String? backupPath;
}
