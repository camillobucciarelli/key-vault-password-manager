import 'package:equatable/equatable.dart';

class VaultAttachment extends Equatable {
  const VaultAttachment({
    required this.key,
    required this.name,
    required this.size,
  });

  final String key;
  final String name;
  final int size;

  @override
  List<Object?> get props => [key, name, size];
}
