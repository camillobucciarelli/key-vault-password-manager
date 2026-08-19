/// FR-1 — In-memory holder for the master password of the currently unlocked
/// vault session.
///
/// Spec 011: secure storage must stop being the transport for the session
/// password across the BLoC boundary. This holder owns the secret in memory for
/// the duration of an unlocked session only. It never writes to disk and never
/// logs its value.
///
/// It lives behind the coordinator layer (constitution principle II): only the
/// session/vault coordinators populate and clear it, and `VaultBloc` reads it
/// through this holder instead of `SecureDataSource`.
///
/// Out of scope (spec 011): locked/obfuscated buffers or zeroing after use.
/// Dart offers no reliable guarantee; this bounds lifetime and location, not the
/// in-process memory representation.
class MasterPasswordSession {
  String? _value;

  /// The current session secret, or `null` when no vault is unlocked.
  ///
  /// An absent value is an error at call sites that require the password, not an
  /// empty password (FR-2). Callers must not substitute `?? ''`.
  String? get value => _value;

  /// True while a vault session holds a secret.
  bool get hasValue => _value != null;

  /// Populate on successful unlock.
  void set(String password) => _value = password;

  /// Clear on lock, database switch, unlock failure and app termination (FR-2).
  void clear() => _value = null;

  /// Never expose the secret through diagnostics (AC-8).
  @override
  String toString() =>
      'MasterPasswordSession(hasValue: ${_value != null})';
}
