import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;

import '../../../../core/utils/mobile_file_storage.dart';
import '../../domain/entities/database_record.dart';
import '../../domain/models/database_import_result.dart';
import '../../domain/usecases/validate_database_usecase.dart';

class StagedDatabaseImport {
  const StagedDatabaseImport({
    required this.imported,
    required this.preferredFileName,
  });

  final DatabaseImportResult imported;
  final String preferredFileName;
}

class DatabaseFileCommit {
  const DatabaseFileCommit({required this.databasePath, this.backupPath});

  final String databasePath;
  final String? backupPath;
}

class DatabaseImportService {
  DatabaseImportService({required this.validateDatabaseUseCase});

  final ValidateDatabaseUseCase validateDatabaseUseCase;

  Future<DatabaseImportResult> importFromSelection({
    required String fileName,
    String? selectedPath,
    List<int>? selectedBytes,
    bool overwriteExisting = false,
  }) async {
    var resolvedPath = await _resolveSelectedDatabasePath(
      fileName: fileName,
      selectedPath: selectedPath,
      selectedBytes: selectedBytes,
    );
    if (resolvedPath == null || resolvedPath.trim().isEmpty) {
      throw Exception('Could not resolve file path.');
    }

    final isValid = await validateDatabaseUseCase(resolvedPath);
    if (!isValid) {
      if (_usesManagedStorage &&
          await MobileFileStorage.isPathInAppDirectory(
            filePath: resolvedPath,
            subdirectory: 'databases',
          )) {
        await MobileFileStorage.deleteFileFromAppDirectory(
          filePath: resolvedPath,
          subdirectory: 'databases',
        );
      }
      throw Exception('The selected file is not a valid KDBX file.');
    }

    if (_usesManagedStorage && overwriteExisting) {
      resolvedPath = await _replaceManagedDatabase(
        validImportPath: resolvedPath,
        fileName: fileName,
      );
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

  Future<StagedDatabaseImport> stageDriveDownload({
    required String fileName,
    required Uint8List bytes,
    required String remoteFileId,
  }) async {
    final stagedPath = await MobileFileStorage.saveBytesToAppDirectory(
      bytes: bytes,
      fileName: fileName,
      subdirectory: 'database_imports',
    );
    if (!await validateDatabaseUseCase(stagedPath)) {
      await MobileFileStorage.deleteFileFromAppDirectory(
        filePath: stagedPath,
        subdirectory: 'database_imports',
      );
      throw Exception(
        'The downloaded Drive file is not a valid KDBX database.',
      );
    }

    return StagedDatabaseImport(
      imported: DatabaseImportResult(
        path: stagedPath,
        fileName: p.basename(fileName),
        fileHash: md5.convert(bytes).toString(),
        sourceType: DatabaseSourceType.drive,
        sourceRef: remoteFileId,
      ),
      preferredFileName: p.basename(fileName),
    );
  }

  Future<StagedDatabaseImport> stageLocalSelection({
    required String fileName,
    String? selectedPath,
    List<int>? selectedBytes,
  }) async {
    final bytes =
        selectedBytes ??
        (selectedPath == null || selectedPath.trim().isEmpty
            ? null
            : await File(selectedPath).readAsBytes());
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Could not resolve file contents.');
    }

    final stagedPath = await MobileFileStorage.saveBytesToAppDirectory(
      bytes: Uint8List.fromList(bytes),
      fileName: fileName,
      subdirectory: 'database_imports',
    );
    if (!await validateDatabaseUseCase(stagedPath)) {
      await MobileFileStorage.deleteFileFromAppDirectory(
        filePath: stagedPath,
        subdirectory: 'database_imports',
      );
      throw Exception('The selected file is not a valid KDBX file.');
    }

    return StagedDatabaseImport(
      imported: DatabaseImportResult(
        path: stagedPath,
        fileName: p.basename(fileName),
        fileHash: md5.convert(bytes).toString(),
        sourceType: DatabaseSourceType.local,
      ),
      preferredFileName: p.basename(fileName),
    );
  }

  Future<String> managedDatabasePath(String fileName) {
    return MobileFileStorage.getPathInAppDirectory(
      fileName: fileName,
      subdirectory: 'databases',
    );
  }

  Future<DatabaseFileCommit> commitStagedDatabase(
    StagedDatabaseImport staged, {
    String? targetPath,
  }) async {
    final stagedFile = File(staged.imported.path);
    if (!await stagedFile.exists()) {
      throw Exception('Staged database is unavailable.');
    }

    if (targetPath == null) {
      final committedPath = await MobileFileStorage.saveBytesToAppDirectory(
        bytes: await stagedFile.readAsBytes(),
        fileName: staged.preferredFileName,
        subdirectory: 'databases',
      );
      await discardStagedDatabase(staged);
      return DatabaseFileCommit(databasePath: committedPath);
    }

    final targetFile = File(targetPath);
    String? backupPath;
    if (await targetFile.exists()) {
      backupPath =
          '$targetPath.import-backup-${DateTime.now().microsecondsSinceEpoch}';
      await targetFile.rename(backupPath);
    }
    try {
      await _moveStagedFile(stagedFile, targetPath);
      return DatabaseFileCommit(
        databasePath: targetPath,
        backupPath: backupPath,
      );
    } catch (_) {
      if (backupPath != null && await File(backupPath).exists()) {
        await File(backupPath).rename(targetPath);
      }
      rethrow;
    }
  }

  Future<void> finalizeDatabaseCommit(DatabaseFileCommit commit) async {
    final backupPath = commit.backupPath;
    if (backupPath != null && await File(backupPath).exists()) {
      await File(backupPath).delete();
    }
  }

  Future<void> rollbackDatabaseCommit(DatabaseFileCommit commit) async {
    final committedFile = File(commit.databasePath);
    final backupPath = commit.backupPath;
    if (backupPath == null) {
      if (await committedFile.exists()) {
        await committedFile.delete();
      }
      return;
    }

    final rollbackFile = File(
      '${commit.databasePath}.import-rollback-${DateTime.now().microsecondsSinceEpoch}',
    );
    if (await committedFile.exists()) {
      await committedFile.rename(rollbackFile.path);
    }
    try {
      await File(backupPath).rename(commit.databasePath);
      if (await rollbackFile.exists()) {
        await rollbackFile.delete();
      }
    } catch (_) {
      if (await rollbackFile.exists() && !await committedFile.exists()) {
        await rollbackFile.rename(commit.databasePath);
      }
      rethrow;
    }
  }

  Future<void> discardStagedDatabase(StagedDatabaseImport staged) async {
    final stagedFile = File(staged.imported.path);
    if (await stagedFile.exists()) {
      await MobileFileStorage.deleteFileFromAppDirectory(
        filePath: stagedFile.path,
        subdirectory: 'database_imports',
      );
    }
  }

  Future<void> _moveStagedFile(File stagedFile, String targetPath) async {
    try {
      await stagedFile.rename(targetPath);
      return;
    } on FileSystemException {
      final installFile = File(
        '$targetPath.import-install-${DateTime.now().microsecondsSinceEpoch}',
      );
      try {
        await installFile.writeAsBytes(
          await stagedFile.readAsBytes(),
          flush: true,
        );
        await installFile.rename(targetPath);
        await stagedFile.delete();
      } catch (_) {
        if (await installFile.exists()) {
          await installFile.delete();
        }
        rethrow;
      }
    }
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

  Future<String?> _resolveSelectedDatabasePath({
    required String fileName,
    required String? selectedPath,
    required List<int>? selectedBytes,
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
      );
    }

    if (selectedBytes == null) {
      return null;
    }

    return MobileFileStorage.saveBytesToAppDirectory(
      bytes: Uint8List.fromList(selectedBytes),
      fileName: fileName,
      subdirectory: 'databases',
    );
  }

  Future<String> _replaceManagedDatabase({
    required String validImportPath,
    required String fileName,
  }) async {
    final targetPath = await MobileFileStorage.getPathInAppDirectory(
      fileName: fileName,
      subdirectory: 'databases',
    );
    if (p.equals(validImportPath, targetPath)) {
      return targetPath;
    }

    final importedFile = File(validImportPath);
    final targetFile = File(targetPath);
    if (!await targetFile.exists()) {
      return (await importedFile.rename(targetPath)).path;
    }

    final backupFile = File(
      '$targetPath.import-backup-${DateTime.now().microsecondsSinceEpoch}',
    );
    await targetFile.rename(backupFile.path);
    try {
      await importedFile.rename(targetPath);
      await backupFile.delete();
      return targetPath;
    } catch (_) {
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await backupFile.rename(targetPath);
      rethrow;
    }
  }

  bool get _isMobilePlatform {
    if (kIsWeb) {
      return false;
    }
    return true;
  }

  bool get _usesManagedStorage => _isMobilePlatform;
}
