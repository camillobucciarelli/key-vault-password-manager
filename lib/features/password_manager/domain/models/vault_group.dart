import 'package:equatable/equatable.dart';

class VaultGroup extends Equatable {
  const VaultGroup({
    required this.id,
    required this.name,
    required this.parentId,
    this.isRecycleBin = false,
  });

  final String id;
  final String name;
  final String? parentId;
  final bool isRecycleBin;

  @override
  List<Object?> get props => [id, name, parentId, isRecycleBin];
}
