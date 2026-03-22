import '../../domain/entities/database_record.dart';

class DatabaseRecordModel {
  const DatabaseRecordModel({
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
  });

  final String databaseId;
  final String canonicalPath;
  final String displayName;
  final String sourceType;
  final String? sourceRef;
  final String? fileHash;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastOpenedAt;
  final bool isFavorite;

  factory DatabaseRecordModel.fromEntity(DatabaseRecord entity) {
    return DatabaseRecordModel(
      databaseId: entity.databaseId,
      canonicalPath: entity.canonicalPath,
      displayName: entity.displayName,
      sourceType: entity.sourceType.name,
      sourceRef: entity.sourceRef,
      fileHash: entity.fileHash,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
      lastOpenedAt: entity.lastOpenedAt,
      isFavorite: entity.isFavorite,
    );
  }

  DatabaseRecord toEntity() {
    final parsedSourceType = DatabaseSourceType.values.firstWhere(
      (value) => value.name == sourceType,
      orElse: () => DatabaseSourceType.local,
    );
    return DatabaseRecord(
      databaseId: databaseId,
      canonicalPath: canonicalPath,
      displayName: displayName,
      sourceType: parsedSourceType,
      sourceRef: sourceRef,
      fileHash: fileHash,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastOpenedAt: lastOpenedAt,
      isFavorite: isFavorite,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'databaseId': databaseId,
      'canonicalPath': canonicalPath,
      'displayName': displayName,
      'sourceType': sourceType,
      'sourceRef': sourceRef,
      'fileHash': fileHash,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'lastOpenedAt': lastOpenedAt?.toUtc().toIso8601String(),
      'isFavorite': isFavorite,
    };
  }

  factory DatabaseRecordModel.fromMap(Map<String, dynamic> map) {
    return DatabaseRecordModel(
      databaseId: map['databaseId'] as String,
      canonicalPath: map['canonicalPath'] as String,
      displayName: map['displayName'] as String,
      sourceType: map['sourceType'] as String,
      sourceRef: map['sourceRef'] as String?,
      fileHash: map['fileHash'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String).toLocal(),
      updatedAt: DateTime.parse(map['updatedAt'] as String).toLocal(),
      lastOpenedAt: map['lastOpenedAt'] == null
          ? null
          : DateTime.parse(map['lastOpenedAt'] as String).toLocal(),
      isFavorite: map['isFavorite'] as bool? ?? false,
    );
  }
}
