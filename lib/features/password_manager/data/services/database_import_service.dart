import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;

import '../../../../core/utils/mobile_file_storage.dart';
import '../../domain/entities/database_record.dart';
import '../../domain/errors/database_access_failure.dart';
import '../../domain/models/database_import_result.dart';
import '../../domain/models/database_import_transaction.dart';
import '../../domain/repositories/database_file_repository.dart';
import '../../domain/usecases/validate_database_usecase.dart';
import 'database_path_mutex.dart';

/// Data-layer implementation of the [DatabaseFileRepository] domain port
/// (C-7). Owns every `dart:io`/`FilePicker`/managed-storage detail that the
/// coordinator used to touch directly.
class DatabaseImportService implements DatabaseFileRepository {
  DatabaseImportService({
    required this.validateDatabaseUseCase,
    DatabasePathMutex? mutex,
  }) : _mutex = mutex ?? DatabasePathMutex();

  final ValidateDatabaseUseCase validateDatabaseUseCase;

  /// spec 008 T105: every file mutation below acquires this lock. NOT
  /// reentrant — locked methods never call each other from inside their
  /// action; multi-step operations (commit, replace) take every involved
  /// path in a single acquisition and use lock-free private helpers.
  final DatabasePathMutex _mutex;

  /// Prospective app-storage path used as the lock identity for writes whose
  /// final name is decided inside `MobileFileStorage` (unique-name suffixing).
  ///
  /// ponytail: locking the base name serializes competing writes of the same
  /// file name, which is the only real contention; a `-1` suffixed sibling
  /// picked inside the lock is a brand-new file no other writer can hold.
  Future<String> _prospectiveAppPath(String fileName, String subdirectory) {
    return MobileFileStorage.getPathInAppDirectory(
      fileName: fileName,
      subdirectory: subdirectory,
    );
  }

  Future<DatabaseAccessFailure?> _validationFailure(String path) async {
    final result = await validateDatabaseUseCase(path);
    return switch (result) {
      DatabaseFileValidation.valid => null,
      DatabaseFileValidation.missing => DatabaseFileMissingFailure(
        p.basename(path),
      ),
      DatabaseFileValidation.invalidStructure => InvalidDatabaseFileFailure(
        p.basename(path),
      ),
    };
  }

  @override
  Future<bool> fileExists(String path) => File(path).exists();

  @override
  Future<String> hashFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return md5.convert(bytes).toString();
  }

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
      throw InvalidDatabaseFileFailure(fileName);
    }

    final failure = await _validationFailure(resolvedPath);
    if (failure != null) {
      if (_usesManagedStorage) {
        // Under managed storage `resolvedPath` is always a file this method
        // just staged itself, via `copyFileToAppDirectory` or
        // `saveBytesToAppDirectory` in `_resolveSelectedDatabasePath`. Gating
        // the cleanup on `isPathInAppDirectory` could therefore only ever be
        // false for a path we could not have produced -- and when it was, the
        // staged file was left behind in `Documents/databases` forever (#46).
        //
        // Deleted directly rather than through `deleteFileFromAppDirectory`,
        // whose own containment guard reintroduces exactly that failure mode.
        try {
          await deleteFile(resolvedPath);
        } catch (_) {
          // Best effort: a cleanup error must never mask the import failure
          // the caller actually needs to see.
        }
      }
      throw failure;
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

  @override
  Future<DatabaseImportResult> openExistingPath(String path) async {
    final trimmedPath = path.trim();
    if (trimmedPath.isEmpty) {
      throw const DatabaseFileMissingFailure('');
    }

    final failure = await _validationFailure(trimmedPath);
    if (failure != null) {
      throw failure;
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

  @override
  Future<StagedDatabaseImport> stageDriveDownload({
    required String fileName,
    required Uint8List bytes,
    required String remoteFileId,
  }) async {
    final prospectivePath = await _prospectiveAppPath(
      fileName,
      'database_imports',
    );
    final stagedPath = await _mutex.withDatabaseLock(
      [prospectivePath],
      () async {
        final stagedPath = await MobileFileStorage.saveBytesToAppDirectory(
          bytes: bytes,
          fileName: fileName,
          subdirectory: 'database_imports',
        );
        final failure = await _validationFailure(stagedPath);
        if (failure != null) {
          await MobileFileStorage.deleteFileFromAppDirectory(
            filePath: stagedPath,
            subdirectory: 'database_imports',
          );
          throw failure;
        }
        return stagedPath;
      },
    );

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

  @override
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
      throw InvalidDatabaseFileFailure(fileName);
    }

    final prospectivePath = await _prospectiveAppPath(
      fileName,
      'database_imports',
    );
    final stagedPath = await _mutex.withDatabaseLock(
      [prospectivePath],
      () async {
        final stagedPath = await MobileFileStorage.saveBytesToAppDirectory(
          bytes: Uint8List.fromList(bytes),
          fileName: fileName,
          subdirectory: 'database_imports',
        );
        final failure = await _validationFailure(stagedPath);
        if (failure != null) {
          await MobileFileStorage.deleteFileFromAppDirectory(
            filePath: stagedPath,
            subdirectory: 'database_imports',
          );
          throw failure;
        }
        return stagedPath;
      },
    );

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

  @override
  Future<String> managedDatabasePath(String fileName) {
    return MobileFileStorage.getPathInAppDirectory(
      fileName: fileName,
      subdirectory: 'databases',
    );
  }

  @override
  Future<DatabaseFileCommit> commitStagedDatabase(
    StagedDatabaseImport staged, {
    String? targetPath,
  }) async {
    final stagedFile = File(staged.imported.path);
    if (!await stagedFile.exists()) {
      throw InvalidDatabaseFileFailure(staged.preferredFileName);
    }

    if (targetPath == null) {
      final prospectivePath = await _prospectiveAppPath(
        staged.preferredFileName,
        'databases',
      );
      return _mutex.withDatabaseLock(
        [stagedFile.path, prospectivePath],
        () async {
          final committedPath = await MobileFileStorage.saveBytesToAppDirectory(
            bytes: await stagedFile.readAsBytes(),
            fileName: staged.preferredFileName,
            subdirectory: 'databases',
          );
          // Inline, lock-free discard: calling the public
          // `discardStagedDatabase` here would nest a second acquisition.
          await _discardStagedDatabaseLockFree(staged);
          return DatabaseFileCommit(databasePath: committedPath);
        },
      );
    }

    return _mutex.withDatabaseLock([stagedFile.path, targetPath], () async {
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
    });
  }

  @override
  Future<void> finalizeDatabaseCommit(DatabaseFileCommit commit) {
    return _mutex.withDatabaseLock([commit.databasePath], () async {
      final backupPath = commit.backupPath;
      if (backupPath != null && await File(backupPath).exists()) {
        await File(backupPath).delete();
      }
    });
  }

  @override
  Future<void> rollbackDatabaseCommit(DatabaseFileCommit commit) {
    return _mutex.withDatabaseLock([commit.databasePath], () async {
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
    });
  }

  @override
  Future<void> discardStagedDatabase(StagedDatabaseImport staged) {
    return _mutex.withDatabaseLock([
      staged.imported.path,
    ], () => _discardStagedDatabaseLockFree(staged));
  }

  Future<void> _discardStagedDatabaseLockFree(
    StagedDatabaseImport staged,
  ) async {
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

  @override
  Future<String> createDatabase({
    required String outputFile,
    required Uint8List databaseBytes,
  }) async {
    if (_usesManagedStorage) {
      final prospectivePath = await _prospectiveAppPath(
        p.basename(outputFile),
        'databases',
      );
      return _mutex.withDatabaseLock([prospectivePath], () {
        return MobileFileStorage.saveBytesToAppDirectory(
          bytes: databaseBytes,
          fileName: p.basename(outputFile),
          subdirectory: 'databases',
        );
      });
    }

    return _mutex.withDatabaseLock([outputFile], () async {
      final file = File(outputFile);
      await file.writeAsBytes(databaseBytes, flush: true);
      return file.path;
    });
  }

  @override
  Future<bool> keyFileExists(String keyFilePath) async {
    try {
      return await File(keyFilePath).exists();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Uint8List> readKeyFileBytes(String keyFilePath) {
    return File(keyFilePath).readAsBytes();
  }

  @override
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

  @override
  Future<String?> ensureManagedKeyFilePath(String? keyFilePath) async {
    final normalized = keyFilePath?.trim();
    if (normalized == null || normalized.isEmpty || !_usesManagedStorage) {
      return normalized;
    }
    try {
      final alreadyManaged = await MobileFileStorage.isPathInAppDirectory(
        filePath: normalized,
        subdirectory: 'keys',
      );
      if (alreadyManaged) {
        return normalized;
      }

      if (!await File(normalized).exists()) {
        return normalized;
      }

      return await MobileFileStorage.copyFileToAppDirectory(
        sourcePath: normalized,
        fallbackFileName: p.basename(normalized),
        subdirectory: 'keys',
      );
    } catch (_) {
      return normalized;
    }
  }

  @override
  Future<void> deleteFile(String path) {
    return _mutex.withDatabaseLock([path], () async {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    });
  }

  @override
  Future<void> copyFile({
    required String sourcePath,
    required String targetPath,
  }) {
    return _mutex.withDatabaseLock([sourcePath, targetPath], () async {
      await File(sourcePath).copy(targetPath);
    });
  }

  @override
  Future<void> renameFile({
    required String sourcePath,
    required String targetPath,
  }) {
    return _mutex.withDatabaseLock([sourcePath, targetPath], () async {
      await File(sourcePath).rename(targetPath);
    });
  }

  @override
  Future<String?> resolveOutputFilePath(String preferredFileName) async {
    final normalizedFileName = _normalizeDatabaseFileName(preferredFileName);
    if (_usesManagedStorage) {
      return normalizedFileName;
    }
    return FilePicker.saveFile(
      dialogTitle: 'Please select an output file:',
      fileName: normalizedFileName,
      type: FileType.custom,
      allowedExtensions: ['kdbx'],
    );
  }

  String _normalizeDatabaseFileName(String value) {
    final trimmed = value.trim();
    final fallback = 'new_database.kdbx';
    if (trimmed.isEmpty) {
      return fallback;
    }

    final normalized = trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (normalized.isEmpty) {
      return fallback;
    }

    return normalized.toLowerCase().endsWith('.kdbx')
        ? normalized
        : '$normalized.kdbx';
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
      await _mutex.withDatabaseLock([webPath], () async {
        await File(webPath).writeAsBytes(selectedBytes, flush: true);
      });
      return webPath;
    }

    if (!_usesManagedStorage) {
      return selectedPath;
    }

    if (selectedPath != null && selectedPath.trim().isNotEmpty) {
      final sourceName = p.basename(selectedPath);
      final prospectivePath = await _prospectiveAppPath(
        sourceName.isEmpty ? fileName : sourceName,
        'databases',
      );
      return _mutex.withDatabaseLock([prospectivePath], () {
        return MobileFileStorage.copyFileToAppDirectory(
          sourcePath: selectedPath,
          fallbackFileName: fileName,
          subdirectory: 'databases',
        );
      });
    }

    if (selectedBytes == null) {
      return null;
    }

    final prospectivePath = await _prospectiveAppPath(fileName, 'databases');
    return _mutex.withDatabaseLock([prospectivePath], () {
      return MobileFileStorage.saveBytesToAppDirectory(
        bytes: Uint8List.fromList(selectedBytes),
        fileName: fileName,
        subdirectory: 'databases',
      );
    });
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

    return _mutex.withDatabaseLock([validImportPath, targetPath], () async {
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
    });
  }

  bool get _isMobilePlatform {
    if (kIsWeb) {
      return false;
    }
    return true;
  }

  bool get _usesManagedStorage => _isMobilePlatform;
}
