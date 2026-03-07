import '../repositories/database_repository.dart';

class GetBiometricProtectionEnabledUseCase {
  final DatabaseRepository repository;

  GetBiometricProtectionEnabledUseCase(this.repository);

  Future<bool> call() async {
    return await repository.getBiometricProtectionEnabled();
  }
}
