import '../../domain/entities/database_security_profile.dart';
import '../../domain/repositories/database_security_repository.dart';
import '../datasources/database_security_local_data_source.dart';
import '../models/database_security_profile_model.dart';

class DatabaseSecurityRepositoryImpl implements DatabaseSecurityRepository {
  DatabaseSecurityRepositoryImpl({required this.localDataSource});

  final DatabaseSecurityLocalDataSource localDataSource;

  @override
  Future<DatabaseSecurityProfile?> getProfile(String databaseId) async {
    if (databaseId.trim().isEmpty) {
      return null;
    }

    final raw = await localDataSource.getProfile(databaseId);
    if (raw == null) {
      return null;
    }
    return DatabaseSecurityProfileModel.fromMap(raw).toEntity();
  }

  @override
  Future<void> saveProfile(DatabaseSecurityProfile profile) async {
    final model = DatabaseSecurityProfileModel.fromEntity(profile);
    await localDataSource.saveProfile(profile.databaseId, model.toMap());
  }

  @override
  Future<void> removeProfile(String databaseId) async {
    if (databaseId.trim().isEmpty) {
      return;
    }
    await localDataSource.removeProfile(databaseId);
  }
}
