import 'package:equatable/equatable.dart';

import '../entities/database_record.dart';

/// C-1 selection metadata. Replaces `List<String> recentDatabasePaths` in
/// coordinator results and `DatabaseSelectionState`.
///
/// Deliberately excludes an item/entry count: reading it before unlock would
/// require decrypting the vault or persisting new decrypted metadata (see
/// spec-003 "Open product assumptions"). `canonicalPath` stays available for
/// overflow actions and semantics but must not be rendered as a row subtitle.
class DatabaseSelectionItem extends Equatable {
  const DatabaseSelectionItem({
    required this.databaseId,
    required this.canonicalPath,
    required this.displayName,
    required this.sourceType,
    this.sourceRef,
    this.isActive = false,
    this.isMissing = false,
    this.biometricProtectionEnabled = false,
    this.keyFileConfigured = false,
    this.lastOpenedAt,
    this.lastSyncAt,
    this.lastSyncError,
  });

  final String databaseId;
  final String canonicalPath;
  final String displayName;
  final DatabaseSourceType sourceType;
  final String? sourceRef;
  final bool isActive;
  final bool isMissing;
  final bool biometricProtectionEnabled;
  final bool keyFileConfigured;
  final DateTime? lastOpenedAt;
  final DateTime? lastSyncAt;
  final String? lastSyncError;

  DatabaseSelectionItem copyWith({
    String? canonicalPath,
    String? displayName,
    bool? isActive,
    bool? isMissing,
    bool? biometricProtectionEnabled,
    bool? keyFileConfigured,
    DateTime? lastOpenedAt,
    DateTime? lastSyncAt,
    String? lastSyncError,
  }) {
    return DatabaseSelectionItem(
      databaseId: databaseId,
      canonicalPath: canonicalPath ?? this.canonicalPath,
      displayName: displayName ?? this.displayName,
      sourceType: sourceType,
      sourceRef: sourceRef,
      isActive: isActive ?? this.isActive,
      isMissing: isMissing ?? this.isMissing,
      biometricProtectionEnabled:
          biometricProtectionEnabled ?? this.biometricProtectionEnabled,
      keyFileConfigured: keyFileConfigured ?? this.keyFileConfigured,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastSyncError: lastSyncError ?? this.lastSyncError,
    );
  }

  @override
  List<Object?> get props => [
    databaseId,
    canonicalPath,
    displayName,
    sourceType,
    sourceRef,
    isActive,
    isMissing,
    biometricProtectionEnabled,
    keyFileConfigured,
    lastOpenedAt,
    lastSyncAt,
    lastSyncError,
  ];
}
