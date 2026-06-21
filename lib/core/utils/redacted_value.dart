/// Value wrapper for Equatable props that must still participate in equality
/// while never being printed by debug stringification.
final class RedactedValue<T> {
  const RedactedValue(this.value, {this.redaction = '<redacted>'});

  final T value;
  final String redaction;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RedactedValue<T> && other.value == value;
  }

  @override
  int get hashCode => Object.hash(T, value);

  @override
  String toString() => redaction;
}
