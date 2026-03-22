import '../entities/database_record.dart';
import '../models/database_dedup_result.dart';
import '../repositories/database_registry_repository.dart';

class ResolveDatabaseDuplicateUseCase {
  ResolveDatabaseDuplicateUseCase(this.repository);

  final DatabaseRegistryRepository repository;

  Future<DatabaseDedupResult> call({
    required DatabaseSourceType sourceType,
    String? sourceRef,
    String? fileHash,
  }) async {
    final normalizedSourceRef = sourceRef?.trim();
    if (normalizedSourceRef != null && normalizedSourceRef.isNotEmpty) {
      final bySource = await repository.findBySource(
        sourceType: sourceType,
        sourceRef: normalizedSourceRef,
      );
      if (bySource != null) {
        return DatabaseDedupResult(
          matchType: DatabaseDuplicateMatchType.source,
          resolution: DatabaseDuplicateResolution.useExisting,
          existingRecord: bySource,
        );
      }
    }

    final normalizedHash = fileHash?.trim();
    if (normalizedHash != null && normalizedHash.isNotEmpty) {
      final byHash = await repository.findByHash(normalizedHash);
      if (byHash != null) {
        return DatabaseDedupResult(
          matchType: DatabaseDuplicateMatchType.hash,
          resolution: DatabaseDuplicateResolution.useExisting,
          existingRecord: byHash,
        );
      }
    }

    return DatabaseDedupResult.noDuplicate;
  }
}
