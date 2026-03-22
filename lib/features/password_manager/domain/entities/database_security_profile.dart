class DatabaseSecurityProfile {
  const DatabaseSecurityProfile({
    required this.databaseId,
    this.keyFilePath,
    this.biometricProtectionEnabled = true,
    this.updatedAt,
  });

  final String databaseId;
  final String? keyFilePath;
  final bool biometricProtectionEnabled;
  final DateTime? updatedAt;

  DatabaseSecurityProfile copyWith({
    String? keyFilePath,
    bool? biometricProtectionEnabled,
    DateTime? updatedAt,
    bool clearKeyFilePath = false,
  }) {
    return DatabaseSecurityProfile(
      databaseId: databaseId,
      keyFilePath: clearKeyFilePath ? null : keyFilePath ?? this.keyFilePath,
      biometricProtectionEnabled:
          biometricProtectionEnabled ?? this.biometricProtectionEnabled,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
