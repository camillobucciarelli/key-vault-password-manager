import 'package:equatable/equatable.dart';
import 'package:password_manager/core/utils/redacted_value.dart';

import '../../../domain/errors/database_access_failure.dart';

/// C-4 unlock phase. `isLoading` is gone — derive it from [phase] via the
/// getters below.
enum UnlockPhase {
  /// Bootstrapping (biometric availability + stored key-file/profile
  /// lookup) before the credential form is usable.
  initializing,

  /// Full-screen biometric gate must be passed before manual credentials
  /// can be submitted.
  biometricGate,

  /// Credential form is interactive and awaiting submission.
  ready,

  /// KDBX read is in flight. Entered *before* the await starts. Submit,
  /// credential edits and back are all disabled in this phase; the read is
  /// not cancellable and the UI must not claim it is.
  decrypting,

  /// Vault opened successfully.
  unlocked,

  /// A database-level typed failure (missing/invalid/corrupt file) makes
  /// the credential form unusable until the user goes back. Wrong
  /// password / missing key file stay in [ready] with an inline field
  /// error instead — see `DatabaseUnlockBloc._phaseForFailure`.
  failure,
}

class DatabaseUnlockState extends Equatable {
  final String databasePath;
  final String? keyFilePath;
  final UnlockPhase phase;
  final bool biometricAvailable;
  final bool biometricPrompted;
  final bool biometricVerified;

  /// C-3 typed failure, when the last error was mappable. Null for
  /// non-typed/business errors (still described in [errorMessage]).
  final DatabaseAccessFailure? failure;
  final String? errorMessage;

  /// C-4: null means indeterminate (always true in spec-003 — the `kdbx`
  /// API exposes no Argon2 progress callback). A non-null value is only
  /// legal in `[0, 1]` and only once a real backend callback exists.
  final double? progress;

  const DatabaseUnlockState({
    required this.databasePath,
    this.keyFilePath,
    this.phase = UnlockPhase.initializing,
    this.biometricAvailable = false,
    this.biometricPrompted = false,
    this.biometricVerified = false,
    this.failure,
    this.errorMessage,
    this.progress,
  });

  factory DatabaseUnlockState.initial({required String databasePath}) {
    return DatabaseUnlockState(databasePath: databasePath);
  }

  bool get isLoading =>
      phase == UnlockPhase.initializing || phase == UnlockPhase.decrypting;
  bool get isDecrypting => phase == UnlockPhase.decrypting;
  bool get requiresBiometricGate => phase == UnlockPhase.biometricGate;
  bool get unlocked => phase == UnlockPhase.unlocked;

  DatabaseUnlockState copyWith({
    String? databasePath,
    String? keyFilePath,
    UnlockPhase? phase,
    bool? biometricAvailable,
    bool? biometricPrompted,
    bool? biometricVerified,
    DatabaseAccessFailure? failure,
    String? errorMessage,
    double? progress,
    bool clearError = false,
    bool clearKeyFilePath = false,
    bool clearProgress = false,
  }) {
    return DatabaseUnlockState(
      databasePath: databasePath ?? this.databasePath,
      keyFilePath: clearKeyFilePath ? null : keyFilePath ?? this.keyFilePath,
      phase: phase ?? this.phase,
      biometricAvailable: biometricAvailable ?? this.biometricAvailable,
      biometricPrompted: biometricPrompted ?? this.biometricPrompted,
      biometricVerified: biometricVerified ?? this.biometricVerified,
      failure: clearError ? null : failure ?? this.failure,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      progress: clearProgress ? null : progress ?? this.progress,
    );
  }

  @override
  List<Object?> get props => [
    databasePath,
    RedactedValue<String?>(keyFilePath, redaction: '<redacted keyFilePath>'),
    phase,
    biometricAvailable,
    biometricPrompted,
    biometricVerified,
    failure,
    errorMessage,
    progress,
  ];
}
