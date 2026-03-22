import '../entities/database_record.dart';

class DatabaseImportResult {
  const DatabaseImportResult({
    required this.path,
    required this.fileName,
    required this.fileHash,
    required this.sourceType,
    this.sourceRef,
  });

  final String path;
  final String fileName;
  final String fileHash;
  final DatabaseSourceType sourceType;
  final String? sourceRef;
}
