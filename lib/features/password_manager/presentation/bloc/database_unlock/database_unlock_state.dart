import 'package:equatable/equatable.dart';
import 'package:password_manager/core/utils/redacted_value.dart';

class DatabaseUnlockState extends Equatable {
  final String databasePath;
  final String? keyFilePath;
  final bool isLoading;
  final bool biometricAvailable;
  final bool biometricPrompted;
  final bool biometricVerified;
  final bool unlocked;
  final String? errorMessage;

  const DatabaseUnlockState({
    required this.databasePath,
    this.keyFilePath,
    this.isLoading = false,
    this.biometricAvailable = false,
    this.biometricPrompted = false,
    this.biometricVerified = false,
    this.unlocked = false,
    this.errorMessage,
  });

  factory DatabaseUnlockState.initial({required String databasePath}) {
    return DatabaseUnlockState(databasePath: databasePath);
  }

  DatabaseUnlockState copyWith({
    String? databasePath,
    String? keyFilePath,
    bool? isLoading,
    bool? biometricAvailable,
    bool? biometricPrompted,
    bool? biometricVerified,
    bool? unlocked,
    String? errorMessage,
    bool clearError = false,
    bool clearKeyFilePath = false,
  }) {
    return DatabaseUnlockState(
      databasePath: databasePath ?? this.databasePath,
      keyFilePath: clearKeyFilePath ? null : keyFilePath ?? this.keyFilePath,
      isLoading: isLoading ?? this.isLoading,
      biometricAvailable: biometricAvailable ?? this.biometricAvailable,
      biometricPrompted: biometricPrompted ?? this.biometricPrompted,
      biometricVerified: biometricVerified ?? this.biometricVerified,
      unlocked: unlocked ?? this.unlocked,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
    databasePath,
    RedactedValue<String?>(keyFilePath, redaction: '<redacted keyFilePath>'),
    isLoading,
    biometricAvailable,
    biometricPrompted,
    biometricVerified,
    unlocked,
    errorMessage,
  ];
}
