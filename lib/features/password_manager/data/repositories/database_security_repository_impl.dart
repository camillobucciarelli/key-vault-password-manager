import '../../domain/entities/database_security_profile.dart';
import '../../domain/repositories/database_security_repository.dart';
import '../datasources/database_security_local_data_source.dart';

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
    return _profileFromMap(raw);
  }

  @override
  Future<void> saveProfile(DatabaseSecurityProfile profile) async {
    await localDataSource.saveProfile(
      profile.databaseId,
      _profileToMap(profile),
    );
  }

  @override
  Future<void> removeProfile(String databaseId) async {
    if (databaseId.trim().isEmpty) {
      return;
    }
    await localDataSource.removeProfile(databaseId);
  }
}

DatabaseSecurityProfile _profileFromMap(Map<String, dynamic> map) =>
    DatabaseSecurityProfile(
      databaseId: map['databaseId'] as String,
      keyFilePath: map['keyFilePath'] as String?,
      biometricProtectionEnabled:
          map['biometricProtectionEnabled'] as bool? ?? true,
      inactivityLockTimeoutSeconds: map['inactivityLockTimeoutSeconds'] as int?,
      updatedAt: map['updatedAt'] == null
          ? null
          : DateTime.parse(map['updatedAt'] as String).toLocal(),
    );

Map<String, dynamic> _profileToMap(DatabaseSecurityProfile profile) => {
  'databaseId': profile.databaseId,
  'keyFilePath': profile.keyFilePath,
  'biometricProtectionEnabled': profile.biometricProtectionEnabled,
  'inactivityLockTimeoutSeconds': profile.inactivityLockTimeoutSeconds,
  'updatedAt': profile.updatedAt?.toUtc().toIso8601String(),
};
