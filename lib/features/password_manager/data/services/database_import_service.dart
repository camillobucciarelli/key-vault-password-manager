import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;

import '../../../../core/utils/mobile_file_storage.dart';
import '../../domain/entities/database_record.dart';
import '../../domain/models/database_import_result.dart';
import '../../domain/usecases/validate_database_usecase.dart';

class DatabaseImportService {
  DatabaseImportService({required this.validateDatabaseUseCase});

  final ValidateDatabaseUseCase validateDatabaseUseCase;

  Future<DatabaseImportResult> importFromSelection({
    required String fileName,
    String? selectedPath,
    List<int>? selectedBytes,
    bool overwriteExisting = false,
  }) async {
    final resolvedPath = await _resolveSelectedDatabasePath(
      fileName: fileName,
      selectedPath: selectedPath,
      selectedBytes: selectedBytes,
      overwriteExisting: overwriteExisting,
    );
    if (resolvedPath == null || resolvedPath.trim().isEmpty) {
      throw Exception('Could not resolve file path.');
    }

    final isValid = await validateDatabaseUseCase(resolvedPath);
    if (!isValid) {
      throw Exception('The selected file is not a valid KDBX file.');
    }

    final bytes = await File(resolvedPath).readAsBytes();
    final fileHash = md5.convert(bytes).toString();
    return DatabaseImportResult(
      path: resolvedPath,
      fileName: p.basename(resolvedPath),
      fileHash: fileHash,
      sourceType: DatabaseSourceType.local,
    );
  }

  Future<DatabaseImportResult> openExistingPath(String path) async {
    final trimmedPath = path.trim();
    if (trimmedPath.isEmpty) {
      throw Exception('Could not resolve file path.');
    }

    final isValid = await validateDatabaseUseCase(trimmedPath);
    if (!isValid) {
      throw Exception('The selected file is not a valid KDBX file.');
    }

    final bytes = await File(trimmedPath).readAsBytes();
    final fileHash = md5.convert(bytes).toString();
    return DatabaseImportResult(
      path: trimmedPath,
      fileName: p.basename(trimmedPath),
      fileHash: fileHash,
      sourceType: DatabaseSourceType.local,
    );
  }

  Future<DatabaseImportResult> importDriveLocalCopy({
    required String localPath,
    required String remoteFileId,
  }) async {
    final managedLocalPath = await ensureManagedDatabasePath(localPath);

    final isValid = await validateDatabaseUseCase(managedLocalPath);
    if (!isValid) {
      throw Exception(
        'The downloaded Drive file is not a valid KDBX database.',
      );
    }

    final bytes = await File(managedLocalPath).readAsBytes();
    final fileHash = md5.convert(bytes).toString();
    return DatabaseImportResult(
      path: managedLocalPath,
      fileName: p.basename(managedLocalPath),
      fileHash: fileHash,
      sourceType: DatabaseSourceType.drive,
      sourceRef: remoteFileId,
    );
  }

  Future<String> createDatabase({
    required String outputFile,
    required Uint8List databaseBytes,
  }) async {
    if (_usesManagedStorage) {
      return MobileFileStorage.saveBytesToAppDirectory(
        bytes: databaseBytes,
        fileName: p.basename(outputFile),
        subdirectory: 'databases',
      );
    }

    final file = File(outputFile);
    await file.writeAsBytes(databaseBytes, flush: true);
    return file.path;
  }

  Future<String> saveKeyFile({
    required String fileName,
    required Uint8List keyFileBytes,
    String? selectedPath,
  }) async {
    if (_usesManagedStorage) {
      final normalizedSelectedPath = selectedPath?.trim();
      if (normalizedSelectedPath != null && normalizedSelectedPath.isNotEmpty) {
        final selectedFile = File(normalizedSelectedPath);
        if (await selectedFile.exists()) {
          return MobileFileStorage.copyFileToAppDirectory(
            sourcePath: normalizedSelectedPath,
            fallbackFileName: fileName,
            subdirectory: 'keys',
          );
        }

        return MobileFileStorage.saveBytesToAppDirectory(
          bytes: keyFileBytes,
          fileName: p.basename(normalizedSelectedPath),
          subdirectory: 'keys',
        );
      }

      return MobileFileStorage.saveBytesToAppDirectory(
        bytes: keyFileBytes,
        fileName: fileName,
        subdirectory: 'keys',
      );
    }

    if (selectedPath == null || selectedPath.trim().isEmpty) {
      throw Exception('No destination selected for key file.');
    }

    final file = File(selectedPath);
    await file.writeAsBytes(keyFileBytes, flush: true);
    return file.path;
  }

  Future<String> ensureManagedDatabasePath(String path) async {
    if (!_usesManagedStorage) {
      return path;
    }

    final expectedManagedPath = await MobileFileStorage.getPathInAppDirectory(
      fileName: p.basename(path),
      subdirectory: 'databases',
    );
    if (p.equals(path, expectedManagedPath)) {
      return path;
    }

    return MobileFileStorage.copyFileToAppDirectory(
      sourcePath: path,
      fallbackFileName: 'database.kdbx',
      subdirectory: 'databases',
    );
  }

  Future<String?> _resolveSelectedDatabasePath({
    required String fileName,
    required String? selectedPath,
    required List<int>? selectedBytes,
    required bool overwriteExisting,
  }) async {
    if (kIsWeb) {
      if (selectedBytes == null || selectedBytes.isEmpty) {
        return null;
      }
      final webDir = await Directory.systemTemp.createTemp('web_db_');
      final webPath = p.join(webDir.path, fileName);
      await File(webPath).writeAsBytes(selectedBytes, flush: true);
      return webPath;
    }

    if (!_usesManagedStorage) {
      return selectedPath;
    }

    if (selectedPath != null && selectedPath.trim().isNotEmpty) {
      return MobileFileStorage.copyFileToAppDirectory(
        sourcePath: selectedPath,
        fallbackFileName: fileName,
        subdirectory: 'databases',
        overwriteIfExists: overwriteExisting,
      );
    }

    if (selectedBytes == null) {
      return null;
    }

    return MobileFileStorage.saveBytesToAppDirectory(
      bytes: Uint8List.fromList(selectedBytes),
      fileName: fileName,
      subdirectory: 'databases',
      overwriteIfExists: overwriteExisting,
    );
  }

  bool get _isMobilePlatform {
    if (kIsWeb) {
      return false;
    }
    return true;
  }

  bool get _usesManagedStorage => _isMobilePlatform;
}
