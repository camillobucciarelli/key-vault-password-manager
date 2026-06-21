import 'package:equatable/equatable.dart';
import 'package:password_manager/core/utils/redacted_value.dart';

class VaultCustomField extends Equatable {
  const VaultCustomField({required this.key, required this.value});

  final String key;
  final String value;

  @override
  List<Object?> get props => [key, RedactedValue(value)];

  @override
  String toString() => 'VaultCustomField(key: $key, value: <redacted>)';
}
