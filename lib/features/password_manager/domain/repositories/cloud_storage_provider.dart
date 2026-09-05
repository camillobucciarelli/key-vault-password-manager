import 'dart:typed_data';

import '../models/remote_file.dart';
import '../models/storage_account_summary.dart';

/// spec 010 §Provider contract semantics — the one cloud storage port.
///
/// Connection/account and object-byte operations live together on purpose:
/// split only after a real second implementation proves they have different
/// lifecycles. Every method either returns provider-neutral data or throws a
/// `CloudStorageException`; SDK classes, HTTP responses, tokens, signed URLs
/// and raw bodies never escape an implementation.
///
/// Remote identity is always `(providerId, remoteFileId)`. Names are display
/// values. The port knows remote bytes, not KDBX parsing, local writes, sync
/// policy or mapping persistence. There is no delete: no current flow deletes
/// a remote file.
abstract class CloudStorageProvider {
  /// Stable persisted machine id (`google_drive`), never a label or type.
  String get providerId;

  Future<bool> isConnected();
  Future<void> connect();
  Future<void> disconnect();
  Future<StorageAccountSummary> getConnectedAccount();

  /// The eligible remote `.kdbx` files the user may choose from, optionally
  /// narrowed by [query]. Immutable snapshot. Spec 013 replaces this with a
  /// select-exactly-one operation.
  Future<List<RemoteFile>> listKdbxFiles({String? query});

  Future<RemoteFile> getFileMetadata(String remoteFileId);

  /// Creates a new object named [name] holding [bytes]; returns fresh metadata.
  Future<RemoteFile> createFile({
    required String name,
    required Uint8List bytes,
  });

  /// Replaces the bytes of [remoteFileId]; returns fresh metadata.
  Future<RemoteFile> updateFile({
    required String remoteFileId,
    required Uint8List bytes,
  });

  Future<Uint8List> downloadFile(String remoteFileId);
}
