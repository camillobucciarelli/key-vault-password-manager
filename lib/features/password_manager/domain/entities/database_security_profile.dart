class DatabaseSecurityProfile {
  const DatabaseSecurityProfile({
    required this.databaseId,
    this.keyFilePath,
    // spec-011 FR-7: persisting the master password requires explicit
    // consent, so the implicit default is always `false`.
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
