import 'package:equatable/equatable.dart';

class DriveRemoteFile extends Equatable {
  const DriveRemoteFile({
    required this.id,
    required this.name,
    this.modifiedTime,
    this.md5Checksum,
    this.size,
  });

  final String id;
  final String name;
  final DateTime? modifiedTime;
  final String? md5Checksum;

  /// File size in bytes. Nullable — the Drive API omits it for some file
  /// types (e.g. Shortcuts, native Docs), though it is normally present for
  /// `.kdbx` binaries.
  final int? size;

  @override
  List<Object?> get props => [id, name, modifiedTime, md5Checksum, size];
}
