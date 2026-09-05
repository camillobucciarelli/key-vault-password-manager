import 'package:equatable/equatable.dart';
import 'package:path/path.dart' as p;
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

  /// spec 014 FR-3: the registry name. The file on disk is an opaque
  /// identifier on mobile, so never render the basename when this is set.
  final String? displayName;
  final String? keyFilePath;
  final UnlockPhase phase;
  final bool biometricAvailable;
  final bool biometricPrompted;
  final bool biometricVerified;

  /// Session-only escape hatch from the biometric gate: the user chose to
  /// unlock with the master password instead. Never persisted — the
  /// security profile's `biometricProtectionEnabled` is untouched, so the
  /// next launch gates on biometrics again.
  final bool manualFallbackRequested;

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
    this.displayName,
    this.keyFilePath,
    this.phase = UnlockPhase.initializing,
    this.biometricAvailable = false,
    this.biometricPrompted = false,
    this.biometricVerified = false,
    this.manualFallbackRequested = false,
    this.failure,
    this.errorMessage,
    this.progress,
  });

  factory DatabaseUnlockState.initial({required String databasePath}) {
    return DatabaseUnlockState(databasePath: databasePath);
  }

  /// What the UI shows for this database. Falls back to the basename, which
  /// is the real name wherever storage is not opaque (desktop).
  String get databaseLabel => displayName ?? p.basename(databasePath);

  bool get isLoading =>
      phase == UnlockPhase.initializing || phase == UnlockPhase.decrypting;
  bool get isDecrypting => phase == UnlockPhase.decrypting;
  bool get requiresBiometricGate => phase == UnlockPhase.biometricGate;
  bool get unlocked => phase == UnlockPhase.unlocked;

  DatabaseUnlockState copyWith({
    String? databasePath,
    String? displayName,
    String? keyFilePath,
    UnlockPhase? phase,
    bool? biometricAvailable,
    bool? biometricPrompted,
    bool? biometricVerified,
    bool? manualFallbackRequested,
    DatabaseAccessFailure? failure,
    String? errorMessage,
    double? progress,
    bool clearError = false,
    bool clearKeyFilePath = false,
    bool clearProgress = false,
  }) {
    return DatabaseUnlockState(
      databasePath: databasePath ?? this.databasePath,
      displayName: displayName ?? this.displayName,
      keyFilePath: keyFilePath ?? (clearKeyFilePath ? null : this.keyFilePath),
      phase: phase ?? this.phase,
      biometricAvailable: biometricAvailable ?? this.biometricAvailable,
      biometricPrompted: biometricPrompted ?? this.biometricPrompted,
      biometricVerified: biometricVerified ?? this.biometricVerified,
      manualFallbackRequested:
          manualFallbackRequested ?? this.manualFallbackRequested,
      failure: failure ?? (clearError ? null : this.failure),
      errorMessage: errorMessage ?? (clearError ? null : this.errorMessage),
      progress: clearProgress ? null : progress ?? this.progress,
    );
  }

  @override
  List<Object?> get props => [
    databasePath,
    displayName,
    RedactedValue<String?>(keyFilePath, redaction: '<redacted keyFilePath>'),
    phase,
    biometricAvailable,
    biometricPrompted,
    biometricVerified,
    manualFallbackRequested,
    failure,
    errorMessage,
    progress,
  ];
}
