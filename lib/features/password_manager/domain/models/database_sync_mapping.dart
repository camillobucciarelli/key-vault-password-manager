import 'dart:convert';

import 'package:equatable/equatable.dart';

class DatabaseSyncMapping extends Equatable {
  const DatabaseSyncMapping({
    required this.databasePath,
    required this.driveFileId,
    required this.driveFileName,
    this.lastSyncedLocalChecksum,
    this.lastSyncedRemoteChecksum,
    this.lastSyncedRemoteModifiedTime,
    this.lastSyncAt,
    this.autoSyncEnabled = true,
    this.lastError,
  });

  final String databasePath;
  final String driveFileId;
  final String driveFileName;
  final String? lastSyncedLocalChecksum;
  final String? lastSyncedRemoteChecksum;
  final DateTime? lastSyncedRemoteModifiedTime;
  final DateTime? lastSyncAt;
  final bool autoSyncEnabled;
  final String? lastError;

  DatabaseSyncMapping copyWith({
    String? databasePath,
    String? driveFileId,
    String? driveFileName,
    String? lastSyncedLocalChecksum,
    String? lastSyncedRemoteChecksum,
    DateTime? lastSyncedRemoteModifiedTime,
    DateTime? lastSyncAt,
    bool? autoSyncEnabled,
    String? lastError,
    bool clearError = false,
  }) {
    return DatabaseSyncMapping(
      databasePath: databasePath ?? this.databasePath,
      driveFileId: driveFileId ?? this.driveFileId,
      driveFileName: driveFileName ?? this.driveFileName,
      lastSyncedLocalChecksum:
          lastSyncedLocalChecksum ?? this.lastSyncedLocalChecksum,
      lastSyncedRemoteChecksum:
          lastSyncedRemoteChecksum ?? this.lastSyncedRemoteChecksum,
      lastSyncedRemoteModifiedTime:
          lastSyncedRemoteModifiedTime ?? this.lastSyncedRemoteModifiedTime,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      lastError: clearError ? null : lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'databasePath': databasePath,
      'driveFileId': driveFileId,
      'driveFileName': driveFileName,
      'lastSyncedLocalChecksum': lastSyncedLocalChecksum,
      'lastSyncedRemoteChecksum': lastSyncedRemoteChecksum,
      'lastSyncedRemoteModifiedTime': lastSyncedRemoteModifiedTime
          ?.toUtc()
          .toIso8601String(),
      'lastSyncAt': lastSyncAt?.toUtc().toIso8601String(),
      'autoSyncEnabled': autoSyncEnabled,
      'lastError': lastError,
    };
  }

  factory DatabaseSyncMapping.fromMap(Map<String, dynamic> map) {
    return DatabaseSyncMapping(
      databasePath: map['databasePath'] as String,
      driveFileId: map['driveFileId'] as String,
      driveFileName: map['driveFileName'] as String,
      lastSyncedLocalChecksum: map['lastSyncedLocalChecksum'] as String?,
      lastSyncedRemoteChecksum: map['lastSyncedRemoteChecksum'] as String?,
      lastSyncedRemoteModifiedTime: map['lastSyncedRemoteModifiedTime'] == null
          ? null
          : DateTime.tryParse(
              map['lastSyncedRemoteModifiedTime'] as String,
            )?.toLocal(),
      lastSyncAt: map['lastSyncAt'] == null
          ? null
          : DateTime.tryParse(map['lastSyncAt'] as String)?.toLocal(),
      autoSyncEnabled: map['autoSyncEnabled'] as bool? ?? true,
      lastError: map['lastError'] as String?,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory DatabaseSyncMapping.fromJson(String source) {
    return DatabaseSyncMapping.fromMap(
      jsonDecode(source) as Map<String, dynamic>,
    );
  }

  @override
  List<Object?> get props => [
    databasePath,
    driveFileId,
    driveFileName,
    lastSyncedLocalChecksum,
    lastSyncedRemoteChecksum,
    lastSyncedRemoteModifiedTime,
    lastSyncAt,
    autoSyncEnabled,
    lastError,
  ];
}

/// Snapshot of both mapping slots involved in a `moveMappingPath` call,
/// exact enough to be inverted byte-for-byte. `sourceBefore`/
/// `destinationBefore` are `null` when no mapping occupied that path before
/// the move — restoring from a `null` snapshot means "delete", never
/// "invent a mapping".
class DatabaseSyncMappingPathMove extends Equatable {
  const DatabaseSyncMappingPathMove({
    required this.fromDatabasePath,
    required this.toDatabasePath,
    required this.sourceBefore,
    required this.destinationBefore,
  });

  final String fromDatabasePath;
  final String toDatabasePath;
  final DatabaseSyncMapping? sourceBefore;
  final DatabaseSyncMapping? destinationBefore;

  @override
  List<Object?> get props => [
    fromDatabasePath,
    toDatabasePath,
    sourceBefore,
    destinationBefore,
  ];
}
