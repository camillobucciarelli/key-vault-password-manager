import 'package:equatable/equatable.dart';

class DriveRemoteFile extends Equatable {
  const DriveRemoteFile({
    required this.id,
    required this.name,
    this.modifiedTime,
    this.md5Checksum,
  });

  final String id;
  final String name;
  final DateTime? modifiedTime;
  final String? md5Checksum;

  @override
  List<Object?> get props => [id, name, modifiedTime, md5Checksum];
}
