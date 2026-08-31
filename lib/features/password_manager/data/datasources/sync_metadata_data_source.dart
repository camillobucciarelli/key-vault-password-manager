import 'dart:convert';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:path/path.dart' as p;
import '../../../../core/utils/managed_storage_root.dart';
import 'metadata_cipher.dart';
import 'secure_data_source.dart';

import '../../../../core/utils/portable_path.dart';
import '../../domain/models/database_sync_mapping.dart';

/// spec-008 T404 — the durable record written **before** a conflict-resolution
/// commit dispatches its upload.
///
/// It exists so a process that dies between the local atomic replace and the
/// mapping finalize can be triaged on the next launch instead of leaving a
/// vault in a state nobody can classify. Everything the triage asks is here:
/// what was written locally, what was sent, what the send expected to replace,
/// which remote file it was sent to, and where the pre-write backup went.
///
/// **Security boundary.** This is persisted unencrypted next to the sync
/// mappings, so it carries checksums, an opaque remote file id and two
/// filesystem paths — and deliberately **no plaintext value, no master
/// password, no key-file bytes or path, and no credential of any kind**.
/// Anything secret placed here would be secret on disk.
///
/// **There is no expected-old-token field, on purpose.** A concurrency token is
/// only ever sent to a backend that declares a conditional write; the one
/// storage backend this app has (Drive) does not, so an expected-old-token
/// column would be null in every row ever written.
class PendingMergeUpload extends Equatable {
  const PendingMergeUpload({
    required this.databasePath,
    required this.remoteFileId,
    required this.mergedChecksum,
    required this.localCommittedChecksum,
    this.expectedOldRemoteChecksum,
    this.backupPath,
    this.outcomeAmbiguous = false,
  });

  /// The local vault this record belongs to. Doubles as the store's key: at
  /// most one dispatch can be in flight per database, because the whole commit
  /// runs under that database's writer lock.
  final String databasePath;

  /// Provider-side id of the file the bytes were sent to. Not a URL and not an
  /// account label.
  final String remoteFileId;

  /// Checksum of the bytes that were dispatched. Recovery compares the
  /// refetched remote against this to answer "did my upload land?".
  final String mergedChecksum;

  /// Checksum of the bytes the atomic replace put on disk. Recovery compares
  /// the CURRENT local file against this to answer "is the local side still
  /// the one this record describes?" — a different question with a different
  /// remedy, which is why it is a separate field even though the two are equal
  /// by construction today (the same bytes are written and sent).
  final String localCommittedChecksum;

  /// What the dispatch expected the remote to hold *before* it landed. `null`
  /// when the provider reported no checksum for the pre-write state.
  final String? expectedOldRemoteChecksum;

  /// The verified pre-write backup, when one was taken. `null` when there was
  /// no existing target to back up.
  final String? backupPath;

  /// True when the dispatch's outcome could not be determined — the transport
  /// failed after the request went out, or the read-back was not executable.
  /// Such a record must not be retried blindly and must not be read as either
  /// applied or failed.
  final bool outcomeAmbiguous;

  /// The one state transition this record has (T406).
  PendingMergeUpload asAmbiguous() => PendingMergeUpload(
    databasePath: databasePath,
    remoteFileId: remoteFileId,
    mergedChecksum: mergedChecksum,
    localCommittedChecksum: localCommittedChecksum,
    expectedOldRemoteChecksum: expectedOldRemoteChecksum,
    backupPath: backupPath,
    outcomeAmbiguous: true,
  );

  Map<String, dynamic> toMap() => {
    'databasePath': databasePath,
    'remoteFileId': remoteFileId,
    'mergedChecksum': mergedChecksum,
    'localCommittedChecksum': localCommittedChecksum,
    'expectedOldRemoteChecksum': expectedOldRemoteChecksum,
    'backupPath': backupPath,
    'outcomeAmbiguous': outcomeAmbiguous,
  };

  factory PendingMergeUpload.fromMap(Map<String, dynamic> map) =>
      PendingMergeUpload(
        databasePath: map['databasePath'] as String,
        remoteFileId: map['remoteFileId'] as String,
        mergedChecksum: map['mergedChecksum'] as String,
        localCommittedChecksum: map['localCommittedChecksum'] as String,
        expectedOldRemoteChecksum: map['expectedOldRemoteChecksum'] as String?,
        backupPath: map['backupPath'] as String?,
        outcomeAmbiguous: map['outcomeAmbiguous'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [
    databasePath,
    remoteFileId,
    mergedChecksum,
    localCommittedChecksum,
    expectedOldRemoteChecksum,
    backupPath,
    outcomeAmbiguous,
  ];
}

abstract class SyncMetadataDataSource {
  // spec 014 FR-6: mappings are keyed by database identifier, not path. The
  // path in the mapping payload is location data, not identity.
  Future<DatabaseSyncMapping?> getMapping(String databaseId);
  Future<void> upsertMapping(String databaseId, DatabaseSyncMapping mapping);
  Future<void> removeMapping(String databaseId);

  /// The [PendingMergeUpload] recorded for [databasePath], if a dispatch was
  /// started and never finalized.
  Future<PendingMergeUpload?> getPendingUpload(String databasePath);

  /// Writes [record], replacing any record for the same database. Called
  /// before the upload request goes out, and again to mark the outcome
  /// ambiguous.
  Future<void> upsertPendingUpload(PendingMergeUpload record);

  /// Drops the record for [databasePath]. Called only once the read-back has
  /// proved the remote holds the dispatched bytes and the mapping is
  /// finalized — never to make a stuck record go away.
  Future<void> clearPendingUpload(String databasePath);

  /// Moves the mapping at [fromDatabasePath] to [toDatabasePath]. Returns a
  /// [DatabaseSyncMappingPathMove] token capturing both slots' prior state,
  /// so a caller that fails a later step can restore them exactly via
  /// [restoreMappingPathMove] — never by guessing a reverse move.
  Future<DatabaseSyncMappingPathMove> moveMappingPath({
    required String fromDatabasePath,
    required String toDatabasePath,
  });

  /// Restores both mapping slots referenced by [move] to their pre-move
  /// state (present -> re-inserted as-is, absent -> removed).
  Future<void> restoreMappingPathMove(DatabaseSyncMappingPathMove move);

  Future<List<DatabaseSyncMapping>> getAllMappings();
}

class SyncMetadataDataSourceImpl implements SyncMetadataDataSource {
  SyncMetadataDataSourceImpl({required SecureDataSource secureDataSource})
    : _store = EncryptedMetadataStore(secureDataSource: secureDataSource);

  final EncryptedMetadataStore _store;

  static const _syncSubdirectory = 'metadata';
  static const _syncFileName = 'sync_mappings.json';
  static const _pendingUploadsFileName = 'pending_uploads.json';

  @override
  Future<DatabaseSyncMapping?> getMapping(String databaseId) async {
    final mappings = await getAllMappings();
    for (final mapping in mappings) {
      if (mapping.databaseId == databaseId) {
        return mapping;
      }
    }
    return null;
  }

  @override
  Future<void> upsertMapping(
    String databaseId,
    DatabaseSyncMapping mapping,
  ) async {
    if (databaseId.trim().isEmpty) {
      throw ArgumentError('databaseId cannot be empty.');
    }
    final stamped = mapping.copyWith(databaseId: databaseId);
    final mappings = await getAllMappings();
    final next = <DatabaseSyncMapping>[];
    var updated = false;
    for (final item in mappings) {
      if (item.databaseId == databaseId) {
        next.add(stamped);
        updated = true;
      } else {
        next.add(item);
      }
    }
    if (!updated) {
      next.add(stamped);
    }

    await _saveMappings(next);
  }

  @override
  Future<void> removeMapping(String databaseId) async {
    final mappings = await getAllMappings();
    final next = mappings
        .where((mapping) => mapping.databaseId != databaseId)
        .toList(growable: false);
    await _saveMappings(next);
  }

  @override
  Future<DatabaseSyncMappingPathMove> moveMappingPath({
    required String fromDatabasePath,
    required String toDatabasePath,
  }) async {
    if (fromDatabasePath.trim().isEmpty || toDatabasePath.trim().isEmpty) {
      throw ArgumentError('Mapping paths cannot be empty.');
    }

    final mappings = await getAllMappings();
    final move = DatabaseSyncMappingPathMove(
      fromDatabasePath: fromDatabasePath,
      toDatabasePath: toDatabasePath,
      sourceBefore: _mappingAt(mappings, fromDatabasePath),
      destinationBefore: _mappingAt(mappings, toDatabasePath),
    );
    if (fromDatabasePath == toDatabasePath || move.sourceBefore == null) {
      return move;
    }

    final next = _replaceMovedMappings(mappings, move);
    try {
      await _saveMappings(next);
    } catch (_) {
      // Best-effort restore of the pre-move file so a write failure never
      // leaves the on-disk mapping file half-mutated relative to `move`.
      await _saveMappings(mappings);
      rethrow;
    }
    return move;
  }

  @override
  Future<void> restoreMappingPathMove(DatabaseSyncMappingPathMove move) async {
    if (move.fromDatabasePath == move.toDatabasePath) {
      return;
    }
    final mappings = await getAllMappings();
    final restored = mappings
        .where(
          (mapping) =>
              mapping.databasePath != move.fromDatabasePath &&
              mapping.databasePath != move.toDatabasePath,
        )
        .toList();
    if (move.sourceBefore != null) {
      restored.add(move.sourceBefore!);
    }
    if (move.destinationBefore != null) {
      restored.add(move.destinationBefore!);
    }
    await _saveMappings(restored);
  }

  DatabaseSyncMapping? _mappingAt(
    List<DatabaseSyncMapping> mappings,
    String path,
  ) {
    for (final mapping in mappings) {
      if (mapping.databasePath == path) {
        return mapping;
      }
    }
    return null;
  }

  List<DatabaseSyncMapping> _replaceMovedMappings(
    List<DatabaseSyncMapping> mappings,
    DatabaseSyncMappingPathMove move,
  ) {
    return [
      ...mappings.where(
        (mapping) =>
            mapping.databasePath != move.fromDatabasePath &&
            mapping.databasePath != move.toDatabasePath,
      ),
      move.sourceBefore!.copyWith(databasePath: move.toDatabasePath),
    ];
  }

  @override
  Future<List<DatabaseSyncMapping>> getAllMappings() async {
    final file = await _syncMappingsFile();
    final raw = await _store.readString(file);
    if (raw == null || raw.trim().isEmpty) {
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
    await _store.writeString(file, encoded);
  }

  @override
  Future<PendingMergeUpload?> getPendingUpload(String databasePath) async {
    for (final record in await _allPendingUploads()) {
      if (record.databasePath == databasePath) {
        return record;
      }
    }
    return null;
  }

  @override
  Future<void> upsertPendingUpload(PendingMergeUpload record) async {
    final existing = await _allPendingUploads();
    await _savePendingUploads([
      ...existing.where((item) => item.databasePath != record.databasePath),
      record,
    ]);
  }

  @override
  Future<void> clearPendingUpload(String databasePath) async {
    final existing = await _allPendingUploads();
    if (!existing.any((item) => item.databasePath == databasePath)) {
      return;
    }
    await _savePendingUploads(
      existing.where((item) => item.databasePath != databasePath).toList(),
    );
  }

  Future<List<PendingMergeUpload>> _allPendingUploads() async {
    final file = await _metadataFile(_pendingUploadsFileName);
    final raw = await _store.readString(file);
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }
    // Both paths are stored portably for the same reason `databasePath` is on
    // a mapping: an iOS app container is relocated under the app's feet, and a
    // record that outlives a relaunch is exactly the one that meets a new
    // container UUID.
    final documentsRoot = await PortablePath.documentsRoot();
    return decoded
        .whereType<Map>()
        .map((item) {
          final record = PendingMergeUpload.fromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );
          final backupPath = record.backupPath;
          return PendingMergeUpload(
            databasePath: PortablePath.decode(
              record.databasePath,
              documentsRoot,
            ),
            remoteFileId: record.remoteFileId,
            mergedChecksum: record.mergedChecksum,
            localCommittedChecksum: record.localCommittedChecksum,
            expectedOldRemoteChecksum: record.expectedOldRemoteChecksum,
            backupPath: backupPath == null
                ? null
                : PortablePath.decode(backupPath, documentsRoot),
            outcomeAmbiguous: record.outcomeAmbiguous,
          );
        })
        .toList(growable: false);
  }

  Future<void> _savePendingUploads(List<PendingMergeUpload> records) async {
    final resolvedRoot = PortablePath.resolveForComparison(
      await PortablePath.documentsRoot(),
    );
    String? encodePath(String? path) => path == null
        ? null
        : PortablePath.encodeWithResolvedRoot(path, resolvedRoot);
    final encoded = jsonEncode([
      for (final record in records)
        record.toMap()
          ..['databasePath'] = encodePath(record.databasePath)
          ..['backupPath'] = encodePath(record.backupPath),
    ]);
    final file = await _metadataFile(_pendingUploadsFileName);
    await _store.writeString(file, encoded);
  }

  Future<File> _syncMappingsFile() => _metadataFile(_syncFileName);

  Future<File> _metadataFile(String name) async {
    final root = await ManagedStorageRoot.resolveDirectory();
    final directory = Directory(p.join(root.path, _syncSubdirectory));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(p.join(directory.path, name));
  }
}
