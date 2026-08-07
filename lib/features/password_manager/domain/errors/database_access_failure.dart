/// C-3 typed file/unlock failures.
///
/// These are the only failure shapes the UI is allowed to render copy for.
/// They implement [Exception] so use cases/data implementations can `throw`
/// them directly at the boundary where the raw platform/package exception is
/// caught, without introducing a parallel `Result`/`Either` wrapper type.
/// Coordinator and BLoC code must never render `e.toString()` for these, and
/// must never log the values they carry (only a basename, never a full path).
sealed class DatabaseAccessFailure implements Exception {
  const DatabaseAccessFailure();
}

/// The database file itself is absent from disk.
final class DatabaseFileMissingFailure extends DatabaseAccessFailure {
  const DatabaseFileMissingFailure(this.basename);

  /// File name only (never a full path) — safe to render and log.
  final String basename;

  @override
  String toString() => 'DatabaseFileMissingFailure($basename)';
}

/// The selected file does not have a valid KDBX structure, or is an
/// unsupported KDBX variant. Distinct from [CorruptDatabaseFailure]: this is
/// raised before the file is accepted as a real vault selection.
final class InvalidDatabaseFileFailure extends DatabaseAccessFailure {
  const InvalidDatabaseFileFailure(this.basename);

  final String basename;

  @override
  String toString() => 'InvalidDatabaseFileFailure($basename)';
}

/// A previously-valid selection failed to parse as KDBX
/// (`KdbxCorruptedFileException` / `KdbxInvalidFileStructure`). Must never be
/// presented to the user as "wrong password".
final class CorruptDatabaseFailure extends DatabaseAccessFailure {
  const CorruptDatabaseFailure(this.basename);

  final String basename;

  @override
  String toString() => 'CorruptDatabaseFailure($basename)';
}

/// The configured/selected key file path does not exist on disk.
final class KeyFileMissingFailure extends DatabaseAccessFailure {
  const KeyFileMissingFailure();

  @override
  String toString() => 'KeyFileMissingFailure()';
}

/// `KdbxInvalidKeyException` — wrong master password and/or key file.
final class InvalidCredentialsFailure extends DatabaseAccessFailure {
  const InvalidCredentialsFailure();

  @override
  String toString() => 'InvalidCredentialsFailure()';
}
