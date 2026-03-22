import '../../domain/entities/database_security_profile.dart';

class DatabaseSecurityProfileModel {
  const DatabaseSecurityProfileModel({
    required this.databaseId,
    this.keyFilePath,
    required this.biometricProtectionEnabled,
    this.updatedAt,
  });

  final String databaseId;
  final String? keyFilePath;
  final bool biometricProtectionEnabled;
  final DateTime? updatedAt;

  factory DatabaseSecurityProfileModel.fromEntity(
    DatabaseSecurityProfile entity,
  ) {
    return DatabaseSecurityProfileModel(
      databaseId: entity.databaseId,
      keyFilePath: entity.keyFilePath,
      biometricProtectionEnabled: entity.biometricProtectionEnabled,
      updatedAt: entity.updatedAt,
    );
  }

  DatabaseSecurityProfile toEntity() {
    return DatabaseSecurityProfile(
      databaseId: databaseId,
      keyFilePath: keyFilePath,
      biometricProtectionEnabled: biometricProtectionEnabled,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'databaseId': databaseId,
      'keyFilePath': keyFilePath,
      'biometricProtectionEnabled': biometricProtectionEnabled,
      'updatedAt': updatedAt?.toUtc().toIso8601String(),
    };
  }

  factory DatabaseSecurityProfileModel.fromMap(Map<String, dynamic> map) {
    return DatabaseSecurityProfileModel(
      databaseId: map['databaseId'] as String,
      keyFilePath: map['keyFilePath'] as String?,
      biometricProtectionEnabled:
          map['biometricProtectionEnabled'] as bool? ?? true,
      updatedAt: map['updatedAt'] == null
          ? null
          : DateTime.parse(map['updatedAt'] as String).toLocal(),
    );
  }
}
