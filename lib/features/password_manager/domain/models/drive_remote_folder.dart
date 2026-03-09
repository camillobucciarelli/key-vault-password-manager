import 'package:equatable/equatable.dart';

class DriveRemoteFolder extends Equatable {
  const DriveRemoteFolder({required this.id, required this.name});

  final String id;
  final String name;

  @override
  List<Object?> get props => [id, name];
}
