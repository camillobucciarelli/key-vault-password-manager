import '../repositories/database_repository.dart';

class SetBiometricProtectionEnabledUseCase {
  final DatabaseRepository repository;

  SetBiometricProtectionEnabledUseCase(this.repository);

  Future<void> call(bool enabled) async {
    return await repository.setBiometricProtectionEnabled(enabled);
  }
}
