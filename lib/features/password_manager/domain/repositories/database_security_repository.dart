import '../entities/database_security_profile.dart';

abstract class DatabaseSecurityRepository {
  Future<DatabaseSecurityProfile?> getProfile(String databaseId);
  Future<void> saveProfile(DatabaseSecurityProfile profile);
  Future<void> removeProfile(String databaseId);
}
