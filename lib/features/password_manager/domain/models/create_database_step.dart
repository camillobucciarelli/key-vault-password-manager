/// FR-2 create-database wizard steps. Non-secret — safe to hold in BLoC
/// state (C-5): the wizard's step position is UI/workflow state, the
/// password itself never is.
enum CreateDatabaseStep {
  /// Step 1 of 3 — name / storage note.
  nameAndStorage,

  /// Step 2 of 3 — master password / confirm / strength.
  masterPassword,

  /// Step 3 of 3 — optional key file, Face ID, auto-lock.
  optionalLocks,
}

/// Password strength category as computed by the screen from the plaintext
/// password (never transmitted). Only the category crosses into BLoC
/// events/state (C-5 "validation facts, not plaintext").
enum PasswordStrengthCategory { weak, fair, good, strong }
