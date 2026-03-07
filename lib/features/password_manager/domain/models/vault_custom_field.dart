import 'package:equatable/equatable.dart';

class VaultCustomField extends Equatable {
  const VaultCustomField({required this.key, required this.value});

  final String key;
  final String value;

  @override
  List<Object?> get props => [key, value];
}
