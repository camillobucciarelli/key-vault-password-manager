class DatabaseSecurityProfile {
  const DatabaseSecurityProfile({
    required this.databaseId,
    this.keyFilePath,
    // spec-011 FR-7: absence of an explicit choice is not consent to persist a
    // secret. A profile only enables biometrics when the user opts in.
    this.biometricProtectionEnabled = false,
    this.inactivityLockTimeoutSeconds,
    this.updatedAt,
  });

  final String databaseId;
  final String? keyFilePath;
  final bool biometricProtectionEnabled;
  final int? inactivityLockTimeoutSeconds;
  final DateTime? updatedAt;

  DatabaseSecurityProfile copyWith({
    String? keyFilePath,
    bool? biometricProtectionEnabled,
    int? inactivityLockTimeoutSeconds,
    DateTime? updatedAt,
    bool clearKeyFilePath = false,
    bool clearInactivityTimeout = false,
  }) {
    return DatabaseSecurityProfile(
      databaseId: databaseId,
      keyFilePath: clearKeyFilePath ? null : keyFilePath ?? this.keyFilePath,
      biometricProtectionEnabled:
          biometricProtectionEnabled ?? this.biometricProtectionEnabled,
      inactivityLockTimeoutSeconds: clearInactivityTimeout
          ? null
          : inactivityLockTimeoutSeconds ?? this.inactivityLockTimeoutSeconds,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
