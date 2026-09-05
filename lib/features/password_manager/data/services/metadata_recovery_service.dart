import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../core/utils/managed_storage_root.dart';
import '../../domain/repositories/metadata_recovery_repository.dart';
import '../datasources/metadata_cipher.dart';
import '../datasources/secure_data_source.dart';

/// spec 014 FR-5 recovery. When the metadata key is lost while its ciphertext
/// remains on disk, every metadata write is refused
/// (`MetadataStorageUnreadableFailure`) and the app can no longer record a
/// database — including through the manual re-selection FR-5 offers as the
/// recovery path.
///
/// This service is that path, and it only ever runs from an explicit user
/// action: it moves the unreadable files aside so the next write mints a
/// fresh key. Files are renamed, never deleted, so they still decrypt if the
/// key ever comes back.
class MetadataRecoveryService implements MetadataRecoveryRepository {
  MetadataRecoveryService({required SecureDataSource secureDataSource})
    : _store = EncryptedMetadataStore(secureDataSource: secureDataSource);

  final EncryptedMetadataStore _store;

  static const _metadataSubdirectory = 'metadata';

  /// True when at least one metadata file is unreadable ciphertext. A store
  /// that merely fails to answer right now is not orphaned — its data is
  /// intact and must not be discarded.
  @override
  Future<bool> hasUnreadableMetadata() async {
    for (final file in await _metadataFiles()) {
      if (await _store.hasOrphanedCiphertext(file)) {
        return true;
      }
    }
    return false;
  }

  /// Moves every unreadable metadata file aside. Returns how many were moved.
  @override
  Future<int> discardUnreadableMetadata() async {
    var moved = 0;
    for (final file in await _metadataFiles()) {
      if (await _store.hasOrphanedCiphertext(file)) {
        await _store.quarantineOrphanedCiphertext(file);
        moved += 1;
      }
    }
    return moved;
  }

  Future<List<File>> _metadataFiles() async {
    final root = await ManagedStorageRoot.resolveDirectory();
    final directory = Directory(p.join(root.path, _metadataSubdirectory));
    if (!await directory.exists()) {
      return const [];
    }
    // `.json` only: already-quarantined `.orphaned-*` files and interrupted
    // `.tmp-*` siblings are not live metadata.
    return directory
        .listSync()
        .whereType<File>()
        .where((file) => p.extension(file.path) == '.json')
        .toList(growable: false);
  }
}
