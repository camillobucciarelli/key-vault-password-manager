import '../entities/database_security_profile.dart';
import '../repositories/database_security_repository.dart';

class SaveDatabaseSecurityProfileUseCase {
  SaveDatabaseSecurityProfileUseCase(this.repository);

  final DatabaseSecurityRepository repository;

  Future<void> call(DatabaseSecurityProfile profile) {
    return repository.saveProfile(profile);
  }
}
