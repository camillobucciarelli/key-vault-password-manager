import '../../domain/entities/database_security_profile.dart';

class DatabaseSecurityProfileModel {
  const DatabaseSecurityProfileModel({
    required this.databaseId,
    this.keyFilePath,
    required this.biometricProtectionEnabled,
    this.inactivityLockTimeoutSeconds,
    this.updatedAt,
  });

  final String databaseId;
  final String? keyFilePath;
  final bool biometricProtectionEnabled;
  final int? inactivityLockTimeoutSeconds;
  final DateTime? updatedAt;

  factory DatabaseSecurityProfileModel.fromEntity(
    DatabaseSecurityProfile entity,
  ) {
    return DatabaseSecurityProfileModel(
      databaseId: entity.databaseId,
      keyFilePath: entity.keyFilePath,
      biometricProtectionEnabled: entity.biometricProtectionEnabled,
      inactivityLockTimeoutSeconds: entity.inactivityLockTimeoutSeconds,
      updatedAt: entity.updatedAt,
    );
  }

  DatabaseSecurityProfile toEntity() {
    return DatabaseSecurityProfile(
      databaseId: databaseId,
      keyFilePath: keyFilePath,
      biometricProtectionEnabled: biometricProtectionEnabled,
      inactivityLockTimeoutSeconds: inactivityLockTimeoutSeconds,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'databaseId': databaseId,
      'keyFilePath': keyFilePath,
      'biometricProtectionEnabled': biometricProtectionEnabled,
      'inactivityLockTimeoutSeconds': inactivityLockTimeoutSeconds,
      'updatedAt': updatedAt?.toUtc().toIso8601String(),
    };
  }

  factory DatabaseSecurityProfileModel.fromMap(Map<String, dynamic> map) {
    return DatabaseSecurityProfileModel(
      databaseId: map['databaseId'] as String,
      keyFilePath: map['keyFilePath'] as String?,
      biometricProtectionEnabled:
          map['biometricProtectionEnabled'] as bool? ?? true,
      inactivityLockTimeoutSeconds:
          map['inactivityLockTimeoutSeconds'] as int?,
      updatedAt: map['updatedAt'] == null
          ? null
          : DateTime.parse(map['updatedAt'] as String).toLocal(),
    );
  }
}
