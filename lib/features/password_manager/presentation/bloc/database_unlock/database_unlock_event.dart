import 'package:equatable/equatable.dart';
import 'package:password_manager/core/utils/redacted_value.dart';

abstract class DatabaseUnlockEvent extends Equatable {
  const DatabaseUnlockEvent();

  @override
  List<Object?> get props => [];
}

class InitializeDatabaseUnlock extends DatabaseUnlockEvent {
  const InitializeDatabaseUnlock();
}

class RetryBiometricAuthentication extends DatabaseUnlockEvent {
  const RetryBiometricAuthentication();
}

class UnlockWithManualCredentials extends DatabaseUnlockEvent {
  final String password;
  final String? keyFilePath;

  const UnlockWithManualCredentials({required this.password, this.keyFilePath});

  @override
  List<Object?> get props => [
    RedactedValue<String>(password),
    RedactedValue<String?>(keyFilePath, redaction: '<redacted keyFilePath>'),
  ];
}

class UpdateKeyFilePath extends DatabaseUnlockEvent {
  final String? keyFilePath;

  const UpdateKeyFilePath(this.keyFilePath);

  @override
  List<Object?> get props => [
    RedactedValue<String?>(keyFilePath, redaction: '<redacted keyFilePath>'),
  ];
}
