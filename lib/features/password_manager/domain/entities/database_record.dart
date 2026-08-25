enum DatabaseSourceType { local, drive, created }

class DatabaseRecord {
  DatabaseRecord({
    required this.databaseId,
    required this.canonicalPath,
    required this.displayName,
    required this.sourceType,
    required this.createdAt,
    required this.updatedAt,
    this.sourceRef,
    this.fileHash,
    this.lastOpenedAt,
    this.isFavorite = false,
  }) {
    if (databaseId.trim().isEmpty) {
      throw ArgumentError.value(databaseId, 'databaseId', 'Cannot be empty.');
    }
    if (canonicalPath.trim().isEmpty) {
      throw ArgumentError.value(
        canonicalPath,
        'canonicalPath',
        'Cannot be empty.',
      );
    }
    if (displayName.trim().isEmpty) {
      throw ArgumentError.value(displayName, 'displayName', 'Cannot be empty.');
    }
  }

  final String databaseId;
  final String canonicalPath;
  final String displayName;
  final DatabaseSourceType sourceType;
  final String? sourceRef;
  final String? fileHash;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastOpenedAt;
  final bool isFavorite;

  DatabaseRecord copyWith({
    String? canonicalPath,
    String? displayName,
    DatabaseSourceType? sourceType,
    String? sourceRef,
    String? fileHash,
    bool clearFileHash = false,
    DateTime? updatedAt,
    DateTime? lastOpenedAt,
    bool? isFavorite,
  }) {
    return DatabaseRecord(
      databaseId: databaseId,
      canonicalPath: canonicalPath ?? this.canonicalPath,
      displayName: displayName ?? this.displayName,
      sourceType: sourceType ?? this.sourceType,
      sourceRef: sourceRef ?? this.sourceRef,
      fileHash: clearFileHash ? null : fileHash ?? this.fileHash,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}
