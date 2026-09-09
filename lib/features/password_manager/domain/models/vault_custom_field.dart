import 'package:equatable/equatable.dart';
import 'package:password_manager/core/utils/redacted_value.dart';

class VaultCustomField extends Equatable {
  const VaultCustomField({
    required this.key,
    required this.value,
    this.isProtected = false,
  });

  final String key;
  final String value;

  /// How the KDBX file persists this field: a `ProtectedValue` (the way the
  /// password is stored) rather than a `PlainValue`. Says nothing about the
  /// in-memory [value], which is a plain string like every other domain
  /// field. Read from the file and written back exactly as held: a save must
  /// never downgrade a protected field to plain (spec 023 T010, SC-008).
  final bool isProtected;

  @override
  List<Object?> get props => [key, RedactedValue(value), isProtected];

  @override
  String toString() =>
      'VaultCustomField(key: $key, value: <redacted>, isProtected: $isProtected)';
}
