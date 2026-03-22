import '../entities/database_security_profile.dart';
import '../repositories/database_security_repository.dart';

class GetDatabaseSecurityProfileUseCase {
  GetDatabaseSecurityProfileUseCase(this.repository);

  final DatabaseSecurityRepository repository;

  Future<DatabaseSecurityProfile?> call(String databaseId) {
    return repository.getProfile(databaseId);
  }
}
