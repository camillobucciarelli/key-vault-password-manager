import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:crypto/crypto.dart';
import 'package:kdbx/kdbx.dart';
import 'package:loggy/loggy.dart';
import 'package:path/path.dart' as p;

import '../../../../core/utils/mobile_file_storage.dart';
import '../../data/datasources/local_data_source.dart';
import '../../data/datasources/secure_data_source.dart';
import '../../data/services/database_import_service.dart';
import '../../domain/entities/database_record.dart';
import '../../domain/entities/database_security_profile.dart';
import '../../domain/models/database_dedup_result.dart';
import '../../domain/models/database_import_result.dart';
import '../../domain/models/drive_remote_file.dart';
import '../../domain/repositories/database_registry_repository.dart';
import '../../domain/repositories/database_security_repository.dart';
import '../../domain/repositories/database_sync_repository.dart';
import '../../domain/usecases/get_active_database_usecase.dart';
import '../../domain/usecases/resolve_database_duplicate_usecase.dart';
import '../../domain/usecases/unlock_database_usecase.dart';
import '../bloc/database_selection/database_selection_event.dart';
import 'apple_autofill_v2_coordinator.dart';

enum DatabaseSessionStatus {
  success,
  error,
  info,
  unselected,
  duplicateDecisionRequired,
}

class DatabaseDuplicatePrompt {
  const DatabaseDuplicatePrompt({
    required this.imported,
    required this.existingRecord,
    required this.clearCredentials,
    this.stagedImport,
  });

  final DatabaseImportResult imported;
  final DatabaseRecord existingRecord;
  final bool clearCredentials;
  final StagedDatabaseImport? stagedImport;
}

class DatabaseSelectionSessionResult {
  const DatabaseSelectionSessionResult({
    required this.status,
    required this.recentDatabasePaths,
    this.path,
    this.message,
    this.promptBiometricSetup = false,
    this.duplicatePrompt,
  });

  final DatabaseSessionStatus status;
  final List<String> recentDatabasePaths;
  final String? path;
  final String? message;
  final bool promptBiometricSetup;
  final DatabaseDuplicatePrompt? duplicatePrompt;
}

class UnlockBootstrapResult {
  const UnlockBootstrapResult({
    required this.keyFilePath,
    required this.biometricRequired,
    required this.biometricAvailable,
  });

  final String? keyFilePath;
  final bool biometricRequired;
  final bool biometricAvailable;
}

abstract class DatabaseSessionCoordinatorContract {
  Future<DatabaseSelectionSessionResult> checkInitialDatabase();

  Future<DatabaseSelectionSessionResult> selectExistingDatabase({
    required String fileName,
    String? selectedPath,
    List<int>? selectedBytes,
    bool overwriteExisting = false,
  });

  Future<DatabaseSelectionSessionResult> openRecentDatabase(String path);

  Future<List<DriveRemoteFile>> listDriveDatabases();

  Future<bool> hasManagedDatabaseNamed(String fileName);

  Future<DatabaseSelectionSessionResult> selectDriveDatabase({
    required String remoteFileId,
    required String remoteFileName,
    required bool overwriteExisting,
  });

  Future<DatabaseSelectionSessionResult> createNewDatabase({
    required String databaseFileName,
    required String password,
    String? keyFilePath,
    required bool biometricProtectionEnabled,
    required bool generateKeyFile,
    String? generatedKeyFilePath,
  });

  Future<DatabaseSelectionSessionResult> removeRecentDatabase({
    required String path,
    required RecentDatabaseRemovalMode mode,
  });

  Future<DatabaseSelectionSessionResult> resolveDuplicateDecision({
    required DatabaseDuplicatePrompt duplicatePrompt,
    required DatabaseDuplicateResolution decision,
  });

  Future<UnlockBootstrapResult> initializeUnlock({
    required String databasePath,
    required bool biometricAvailable,
  });

  Future<void> updateKeyFilePath({
    required String databasePath,
    required String? keyFilePath,
  });

  Future<void> updateBiometricProtection({
    required String databasePath,
    required bool enabled,
  });

  Future<void> unlockWithManualCredentials({
    required String databasePath,
    required String password,
    required String? keyFilePath,
  });

  Future<void> unlockWithStoredCredentials({
    required String databasePath,
    required String? keyFilePath,
  });

  Future<bool> hasStoredMasterPassword();

  Future<Set<String>> getProtectedKeyFilePaths();
}

class DatabaseSessionCoordinator implements DatabaseSessionCoordinatorContract {
  DatabaseSessionCoordinator({
    required this.localDataSource,
    required this.databaseRegistryRepository,
    required this.databaseSecurityRepository,
    required this.getActiveDatabaseUseCase,
    required this.secureDataSource,
    required this.databaseImportService,
    required this.resolveDatabaseDuplicateUseCase,
    required this.databaseSyncRepository,
    required this.unlockDatabaseUseCase,
    this.appleAutofillV2Coordinator = const NoopAppleAutofillV2Coordinator(),
  });

  final LocalDataSource localDataSource;
  final DatabaseRegistryRepository databaseRegistryRepository;
  final DatabaseSecurityRepository databaseSecurityRepository;
  final GetActiveDatabaseUseCase getActiveDatabaseUseCase;
  final SecureDataSource secureDataSource;
  final DatabaseImportService databaseImportService;
  final ResolveDatabaseDuplicateUseCase resolveDatabaseDuplicateUseCase;
  final DatabaseSyncRepository databaseSyncRepository;
  final UnlockDatabaseUseCase unlockDatabaseUseCase;
  final AppleAutofillV2CoordinatorContract appleAutofillV2Coordinator;

  @override
  Future<DatabaseSelectionSessionResult> checkInitialDatabase() async {
    final recent = await _loadRecentDatabasePaths();
    final activeRecord = await getActiveDatabaseUseCase();
    final activePath = activeRecord?.canonicalPath;
    final validActivePath =
        activePath != null && _containsPath(recent, activePath)
        ? activePath
        : null;

    if (recent.length > 1 && validActivePath == null) {
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.unselected,
        recentDatabasePaths: recent,
      );
    }

    final path = validActivePath ?? (recent.length == 1 ? recent.first : null);

    if (path == null || path.isEmpty) {
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.unselected,
        recentDatabasePaths: recent,
      );
    }

    try {
      final usesFallback =
          activePath == null ||
          !p.equals(p.normalize(activePath), p.normalize(path));
      if (usesFallback) {
        await _clearSessionCredentials();
      }
      return await _openExistingDatabase(path, clearCredentials: false);
    } catch (e) {
      final updatedRecent = await _loadRecentDatabasePaths();
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.error,
        message: 'Database file not found or corrupted.',
        recentDatabasePaths: updatedRecent,
      );
    }
  }

  bool _containsPath(List<String> paths, String target) {
    final normalizedTarget = p.normalize(target.trim());
    return paths.any(
      (path) => p.equals(p.normalize(path.trim()), normalizedTarget),
    );
  }

  @override
  Future<DatabaseSelectionSessionResult> selectExistingDatabase({
    required String fileName,
    String? selectedPath,
    List<int>? selectedBytes,
    bool overwriteExisting = false,
  }) async {
    final staged = await databaseImportService.stageLocalSelection(
      fileName: fileName,
      selectedPath: selectedPath,
      selectedBytes: selectedBytes,
    );
    final dedup = await resolveDatabaseDuplicateUseCase(
      sourceType: staged.imported.sourceType,
      sourceRef: staged.imported.sourceRef,
      fileHash: staged.imported.fileHash,
    );
    if (dedup.hasDuplicate) {
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.duplicateDecisionRequired,
        message:
            'A database with the same source or content already exists. Choose how to continue.',
        recentDatabasePaths: await _loadRecentDatabasePaths(),
        duplicatePrompt: DatabaseDuplicatePrompt(
          imported: staged.imported,
          existingRecord: dedup.existingRecord!,
          clearCredentials: true,
          stagedImport: staged,
        ),
      );
    }
    return _commitStagedImport(
      staged: staged,
      overwriteExisting: overwriteExisting,
    );
  }

  @override
  Future<DatabaseSelectionSessionResult> openRecentDatabase(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.unselected,
        recentDatabasePaths: await _loadRecentDatabasePaths(),
      );
    }

    return _openExistingDatabase(trimmed, clearCredentials: true);
  }

  Future<DatabaseSelectionSessionResult> _openExistingDatabase(
    String path, {
    required bool clearCredentials,
  }) async {
    final imported = await databaseImportService.openExistingPath(path);
    final existingRecord = await _findRecordByPath(imported.path);
    final now = DateTime.now();
    final recordToSave =
        existingRecord?.copyWith(
          canonicalPath: imported.path,
          displayName: imported.fileName,
          fileHash: imported.fileHash,
          updatedAt: now,
          lastOpenedAt: now,
        ) ??
        DatabaseRecord(
          databaseId: _generateDatabaseId(),
          canonicalPath: imported.path,
          displayName: imported.fileName,
          sourceType: imported.sourceType,
          sourceRef: imported.sourceRef,
          fileHash: imported.fileHash,
          createdAt: now,
          updatedAt: now,
          lastOpenedAt: now,
        );

    await databaseRegistryRepository.upsert(recordToSave);
    await databaseRegistryRepository.setActive(recordToSave.databaseId);
    await localDataSource.cacheDatabasePath(recordToSave.canonicalPath);
    if (clearCredentials) {
      await localDataSource.cacheKeyFilePath(null);
      await secureDataSource.clearMasterPassword();
      await appleAutofillV2Coordinator.clearCredentials();
    }

    return DatabaseSelectionSessionResult(
      status: DatabaseSessionStatus.success,
      path: recordToSave.canonicalPath,
      recentDatabasePaths: await _loadRecentDatabasePaths(),
    );
  }

  @override
  Future<List<DriveRemoteFile>> listDriveDatabases() async {
    if (!await databaseSyncRepository.isConnected()) {
      await databaseSyncRepository.connect();
    }
    return databaseSyncRepository.listRemoteFiles();
  }

  @override
  Future<bool> hasManagedDatabaseNamed(String fileName) async {
    final path = await databaseImportService.managedDatabasePath(fileName);
    return File(path).exists();
  }

  @override
  Future<DatabaseSelectionSessionResult> selectDriveDatabase({
    required String remoteFileId,
    required String remoteFileName,
    required bool overwriteExisting,
  }) async {
    final bytes = await databaseSyncRepository.downloadRemoteFile(remoteFileId);
    final staged = await databaseImportService.stageDriveDownload(
      fileName: remoteFileName,
      bytes: bytes,
      remoteFileId: remoteFileId,
    );
    final dedup = await resolveDatabaseDuplicateUseCase(
      sourceType: staged.imported.sourceType,
      sourceRef: staged.imported.sourceRef,
      fileHash: staged.imported.fileHash,
    );
    if (dedup.hasDuplicate) {
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.duplicateDecisionRequired,
        message:
            'A database with the same source or content already exists. Choose how to continue.',
        recentDatabasePaths: await _loadRecentDatabasePaths(),
        duplicatePrompt: DatabaseDuplicatePrompt(
          imported: staged.imported,
          existingRecord: dedup.existingRecord!,
          clearCredentials: true,
          stagedImport: staged,
        ),
      );
    }
    return _commitStagedImport(
      staged: staged,
      overwriteExisting: overwriteExisting,
    );
  }

  Future<DatabaseSelectionSessionResult> _commitStagedImport({
    required StagedDatabaseImport staged,
    required bool overwriteExisting,
    DatabaseDuplicateResolution? decision,
    DatabaseRecord? duplicateRecord,
  }) async {
    if (decision == DatabaseDuplicateResolution.cancel) {
      await databaseImportService.discardStagedDatabase(staged);
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.unselected,
        recentDatabasePaths: await _loadRecentDatabasePaths(),
      );
    }

    if (decision == DatabaseDuplicateResolution.useExisting &&
        duplicateRecord != null) {
      try {
        final now = DateTime.now();
        await databaseRegistryRepository.upsert(
          duplicateRecord.copyWith(updatedAt: now, lastOpenedAt: now),
        );
        await databaseRegistryRepository.setActive(duplicateRecord.databaseId);
        await localDataSource.cacheDatabasePath(duplicateRecord.canonicalPath);
        await _clearSessionCredentials();
        final recentDatabasePaths = await _loadRecentDatabasePaths();
        if (staged.imported.sourceType == DatabaseSourceType.drive) {
          await databaseSyncRepository.linkDatabaseToDrive(
            databasePath: duplicateRecord.canonicalPath,
            remoteFileId: staged.imported.sourceRef,
          );
        }
        return DatabaseSelectionSessionResult(
          status: DatabaseSessionStatus.success,
          path: duplicateRecord.canonicalPath,
          recentDatabasePaths: recentDatabasePaths,
          promptBiometricSetup:
              staged.imported.sourceType == DatabaseSourceType.drive,
          message: 'Existing database reused to avoid duplicates.',
        );
      } finally {
        try {
          await databaseImportService.discardStagedDatabase(staged);
        } catch (_) {}
      }
    }

    String? targetPath;
    if (decision == DatabaseDuplicateResolution.replaceExisting &&
        duplicateRecord != null) {
      targetPath = duplicateRecord.canonicalPath;
    } else if (decision != DatabaseDuplicateResolution.keepBoth &&
        overwriteExisting) {
      targetPath = await databaseImportService.managedDatabasePath(
        staged.preferredFileName,
      );
    }

    final originalRecord = targetPath == null
        ? null
        : await _findRecordByPath(targetPath);
    final recordToReplace = decision == DatabaseDuplicateResolution.keepBoth
        ? originalRecord
        : duplicateRecord ?? originalRecord;
    final originalProfile = recordToReplace == null
        ? null
        : await databaseSecurityRepository.getProfile(
            recordToReplace.databaseId,
          );
    final originalActive = await getActiveDatabaseUseCase();
    final originalKeyFilePath = await localDataSource.getCachedKeyFilePath();
    final originalPassword = await secureDataSource.getMasterPassword();
    final commit = await databaseImportService.commitStagedDatabase(
      staged,
      targetPath: targetPath,
    );
    final now = DateTime.now();
    final recordToSave =
        (recordToReplace ??
                DatabaseRecord(
                  databaseId: _generateDatabaseId(),
                  canonicalPath: commit.databasePath,
                  displayName: p.basename(commit.databasePath),
                  sourceType: staged.imported.sourceType,
                  sourceRef: staged.imported.sourceRef,
                  fileHash: staged.imported.fileHash,
                  createdAt: now,
                  updatedAt: now,
                  lastOpenedAt: now,
                ))
            .copyWith(
              canonicalPath: commit.databasePath,
              displayName: p.basename(commit.databasePath),
              sourceType: staged.imported.sourceType,
              sourceRef: staged.imported.sourceRef,
              fileHash: staged.imported.fileHash,
              updatedAt: now,
              lastOpenedAt: now,
            );

    try {
      await databaseRegistryRepository.upsert(recordToSave);
      if (originalRecord != null &&
          originalRecord.fileHash != staged.imported.fileHash) {
        await databaseSecurityRepository.removeProfile(
          originalRecord.databaseId,
        );
      }
      await databaseRegistryRepository.setActive(recordToSave.databaseId);
      await localDataSource.cacheDatabasePath(recordToSave.canonicalPath);
      await _clearSessionCredentials();
      final recentDatabasePaths = await _loadRecentDatabasePaths();
      if (staged.imported.sourceType == DatabaseSourceType.drive) {
        await databaseSyncRepository.linkDatabaseToDrive(
          databasePath: recordToSave.canonicalPath,
          remoteFileId: staged.imported.sourceRef,
        );
      }
      try {
        await databaseImportService.finalizeDatabaseCommit(commit);
      } catch (_) {
        // Database and metadata are committed. Keep bounded backup for recovery.
      }
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.success,
        path: recordToSave.canonicalPath,
        recentDatabasePaths: recentDatabasePaths,
        promptBiometricSetup:
            staged.imported.sourceType == DatabaseSourceType.drive,
        message: decision == DatabaseDuplicateResolution.keepBoth
            ? 'Duplicate detected. Kept both databases as requested.'
            : decision == DatabaseDuplicateResolution.replaceExisting
            ? 'Duplicate detected. Existing database replaced.'
            : null,
      );
    } catch (_) {
      try {
        await databaseImportService.rollbackDatabaseCommit(commit);
      } catch (_) {}
      try {
        if (recordToReplace == null) {
          await databaseRegistryRepository.remove(recordToSave.databaseId);
        } else {
          await databaseRegistryRepository.upsert(recordToReplace);
        }
        await databaseRegistryRepository.setActive(originalActive?.databaseId);
      } catch (_) {}
      try {
        if (recordToReplace != null) {
          if (originalProfile == null) {
            await databaseSecurityRepository.removeProfile(
              recordToReplace.databaseId,
            );
          } else {
            await databaseSecurityRepository.saveProfile(originalProfile);
          }
        }
      } catch (_) {}
      try {
        await localDataSource.cacheDatabasePath(
          originalActive?.canonicalPath ?? '',
        );
        await localDataSource.cacheKeyFilePath(originalKeyFilePath);
        if (originalPassword == null) {
          await secureDataSource.clearMasterPassword();
        } else {
          await secureDataSource.saveMasterPassword(originalPassword);
        }
      } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<DatabaseSelectionSessionResult> createNewDatabase({
    required String databaseFileName,
    required String password,
    String? keyFilePath,
    required bool biometricProtectionEnabled,
    required bool generateKeyFile,
    String? generatedKeyFilePath,
  }) async {
    var outputFile = await _resolveOutputFilePath(databaseFileName);
    if (outputFile == null || outputFile.trim().isEmpty) {
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.unselected,
        recentDatabasePaths: await _loadRecentDatabasePaths(),
      );
    }

    if (!outputFile.toLowerCase().endsWith('.kdbx')) {
      outputFile += '.kdbx';
    }

    String? selectedKeyFilePath;
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      selectedKeyFilePath = await _prepareKeyFilePath(
        keyFilePath: keyFilePath,
        generateKeyFile: generateKeyFile,
        generatedKeyFilePath: generatedKeyFilePath,
      );
    }

    final credentials = Credentials.composite(
      ProtectedValue.fromString(password),
      selectedKeyFilePath == null || selectedKeyFilePath.trim().isEmpty
          ? null
          : await File(selectedKeyFilePath).readAsBytes(),
    );
    final kdbx = KdbxFormat().create(credentials, 'New Database');
    final savedBytes = await kdbx.save();
    outputFile = await databaseImportService.createDatabase(
      outputFile: outputFile,
      databaseBytes: savedBytes,
    );

    final fileHash = await _hashFile(outputFile);
    final imported = DatabaseImportResult(
      path: outputFile,
      fileName: p.basename(outputFile),
      fileHash: fileHash,
      sourceType: DatabaseSourceType.created,
    );
    final result = await _applyImportedDatabase(
      imported,
      clearCredentials: false,
    );

    if (result.path != null) {
      await _saveSecurityProfile(
        path: result.path!,
        keyFilePath: selectedKeyFilePath,
        biometricProtectionEnabled: biometricProtectionEnabled,
      );
      await secureDataSource.saveMasterPassword(password);
      await localDataSource.cacheKeyFilePath(selectedKeyFilePath);
    }

    return DatabaseSelectionSessionResult(
      status: result.status,
      path: result.path,
      recentDatabasePaths: result.recentDatabasePaths,
      message: result.path == null
          ? result.message
          : _buildCreationMessage(
              databasePath: result.path!,
              keyFilePath: selectedKeyFilePath,
            ),
    );
  }

  @override
  Future<DatabaseSelectionSessionResult> removeRecentDatabase({
    required String path,
    required RecentDatabaseRemovalMode mode,
  }) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.unselected,
        recentDatabasePaths: await _loadRecentDatabasePaths(),
      );
    }

    var userMessage = 'Database removed from recent list.';
    final activeRecord = await getActiveDatabaseUseCase();
    if (activeRecord != null &&
        _containsPath([activeRecord.canonicalPath], trimmed)) {
      await localDataSource.cacheDatabasePath('');
      await localDataSource.cacheKeyFilePath(null);
      await secureDataSource.clearMasterPassword();
      await databaseRegistryRepository.setActive(null);
    }

    await _removeRecordByPath(trimmed);
    await appleAutofillV2Coordinator.clearCredentials();
    try {
      await databaseSyncRepository.removeMapping(trimmed);
    } catch (e, st) {
      logWarning(
        'Unable to remove sync mapping while deleting recent DB.',
        e,
        st,
      );
    }

    if (mode == RecentDatabaseRemovalMode.removeAndDeleteFile) {
      final file = File(trimmed);
      if (await file.exists()) {
        await file.delete();
        userMessage = 'Database removed from list and file deleted.';
      } else {
        userMessage = 'Database removed from list. File was already missing.';
      }
    }

    return DatabaseSelectionSessionResult(
      status: DatabaseSessionStatus.info,
      message: userMessage,
      recentDatabasePaths: await _loadRecentDatabasePaths(),
    );
  }

  @override
  Future<UnlockBootstrapResult> initializeUnlock({
    required String databasePath,
    required bool biometricAvailable,
  }) async {
    final record = await _findRecordByPath(databasePath);
    final profile = record == null
        ? null
        : await databaseSecurityRepository.getProfile(record.databaseId);

    final profileKeyFilePath = _normalizeKeyFilePath(profile?.keyFilePath);
    var keyFilePath = profileKeyFilePath;
    var profileKeyFileWasMissing = false;

    if (profileKeyFilePath != null &&
        !await _keyFileExists(profileKeyFilePath)) {
      keyFilePath = null;
      profileKeyFileWasMissing = true;
    }

    final cachedKeyFilePath = _normalizeKeyFilePath(
      await localDataSource.getCachedKeyFilePath(),
    );
    var cachedKeyFileWasMissing = false;
    if (keyFilePath == null && record == null && cachedKeyFilePath != null) {
      if (await _keyFileExists(cachedKeyFilePath)) {
        keyFilePath = cachedKeyFilePath;
      } else {
        cachedKeyFileWasMissing = true;
      }
    }

    final selectedKeyFileNeedsSync =
        record != null && !_sameKeyFilePath(cachedKeyFilePath, keyFilePath);

    if (profileKeyFileWasMissing ||
        cachedKeyFileWasMissing ||
        selectedKeyFileNeedsSync) {
      await localDataSource.cacheKeyFilePath(keyFilePath);
      if (record != null && profileKeyFileWasMissing) {
        await _saveSecurityProfile(
          path: record.canonicalPath,
          keyFilePath: keyFilePath,
          biometricProtectionEnabled: null,
        );
      }
    }

    final biometricRequired = profile?.biometricProtectionEnabled ?? false;
    return UnlockBootstrapResult(
      keyFilePath: keyFilePath,
      biometricRequired: biometricRequired,
      biometricAvailable: biometricAvailable,
    );
  }

  @override
  Future<void> updateKeyFilePath({
    required String databasePath,
    required String? keyFilePath,
  }) async {
    final normalizedKeyFilePath = _normalizeKeyFilePath(keyFilePath);
    if (normalizedKeyFilePath != null &&
        !await _keyFileExists(normalizedKeyFilePath)) {
      throw Exception('Selected key file not found.');
    }

    final persistedKeyFilePath = await _ensureManagedKeyFilePath(
      normalizedKeyFilePath,
    );

    await localDataSource.cacheKeyFilePath(persistedKeyFilePath);
    final record = await _findRecordByPath(databasePath);
    if (record == null) {
      return;
    }
    await _saveSecurityProfile(
      path: record.canonicalPath,
      keyFilePath: persistedKeyFilePath,
      biometricProtectionEnabled: null,
    );
  }

  @override
  Future<void> updateBiometricProtection({
    required String databasePath,
    required bool enabled,
  }) async {
    final record = await _findRecordByPath(databasePath);
    if (record == null) {
      return;
    }
    final existing = await databaseSecurityRepository.getProfile(
      record.databaseId,
    );
    final profile =
        (existing ??
                DatabaseSecurityProfile(
                  databaseId: record.databaseId,
                  biometricProtectionEnabled: enabled,
                ))
            .copyWith(
              biometricProtectionEnabled: enabled,
              updatedAt: DateTime.now(),
            );
    await databaseSecurityRepository.saveProfile(profile);
  }

  @override
  Future<void> unlockWithManualCredentials({
    required String databasePath,
    required String password,
    required String? keyFilePath,
  }) async {
    final persistedKeyFilePath = await _ensureManagedKeyFilePath(keyFilePath);
    await unlockDatabaseUseCase(
      databasePath: databasePath,
      password: password,
      keyFilePath: persistedKeyFilePath,
    );
    await localDataSource.cacheKeyFilePath(persistedKeyFilePath);
    await secureDataSource.saveMasterPassword(password);
    await _saveSecurityProfile(
      path: databasePath,
      keyFilePath: persistedKeyFilePath,
      biometricProtectionEnabled: null,
    );
  }

  @override
  Future<void> unlockWithStoredCredentials({
    required String databasePath,
    required String? keyFilePath,
  }) async {
    final storedPassword = await secureDataSource.getMasterPassword() ?? '';
    await unlockDatabaseUseCase(
      databasePath: databasePath,
      password: storedPassword,
      keyFilePath: keyFilePath,
    );
  }

  @override
  Future<bool> hasStoredMasterPassword() async {
    final value = await secureDataSource.getMasterPassword();
    return value != null && value.isNotEmpty;
  }

  @override
  Future<Set<String>> getProtectedKeyFilePaths() async {
    final protectedPaths = <String>{};
    for (final record in await databaseRegistryRepository.list()) {
      final profile = await databaseSecurityRepository.getProfile(
        record.databaseId,
      );
      final path = _normalizeKeyFilePath(profile?.keyFilePath);
      if (path != null) {
        protectedPaths.add(p.normalize(path));
      }
    }
    return protectedPaths;
  }

  Future<void> _clearSessionCredentials() async {
    await localDataSource.cacheKeyFilePath(null);
    await secureDataSource.clearMasterPassword();
    await appleAutofillV2Coordinator.clearCredentials();
  }

  Future<DatabaseSelectionSessionResult> _applyImportedDatabase(
    DatabaseImportResult imported, {
    required bool clearCredentials,
    DatabaseDuplicateResolution? duplicateResolution,
  }) async {
    final dedup = await resolveDatabaseDuplicateUseCase(
      sourceType: imported.sourceType,
      sourceRef: imported.sourceRef,
      fileHash: imported.fileHash,
    );

    if (dedup.hasDuplicate && duplicateResolution == null) {
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.duplicateDecisionRequired,
        message:
            'A database with the same source or content already exists. Choose how to continue.',
        recentDatabasePaths: await _loadRecentDatabasePaths(),
        duplicatePrompt: DatabaseDuplicatePrompt(
          imported: imported,
          existingRecord: dedup.existingRecord!,
          clearCredentials: clearCredentials,
        ),
      );
    }

    if (duplicateResolution == DatabaseDuplicateResolution.cancel) {
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.unselected,
        recentDatabasePaths: await _loadRecentDatabasePaths(),
      );
    }

    final existingPathRecord = await _findRecordByPath(imported.path);
    final selectedRecord = !dedup.hasDuplicate && existingPathRecord != null
        ? existingPathRecord
        : (!dedup.hasDuplicate ||
              duplicateResolution == DatabaseDuplicateResolution.keepBoth)
        ? DatabaseRecord(
            databaseId: _generateDatabaseId(),
            canonicalPath: imported.path,
            displayName: imported.fileName,
            sourceType: imported.sourceType,
            sourceRef: imported.sourceRef,
            fileHash: imported.fileHash,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            lastOpenedAt: DateTime.now(),
          )
        : dedup.existingRecord!;

    if (!dedup.hasDuplicate &&
        existingPathRecord != null &&
        existingPathRecord.fileHash != imported.fileHash) {
      await databaseSecurityRepository.removeProfile(
        existingPathRecord.databaseId,
      );
    }

    final useExisting =
        dedup.hasDuplicate &&
        duplicateResolution == DatabaseDuplicateResolution.useExisting;
    final now = DateTime.now();
    final recordToSave = useExisting
        ? selectedRecord.copyWith(updatedAt: now, lastOpenedAt: now)
        : selectedRecord.copyWith(
            canonicalPath: imported.path,
            displayName: imported.fileName,
            sourceType: imported.sourceType,
            sourceRef: imported.sourceRef,
            fileHash: imported.fileHash.isEmpty
                ? selectedRecord.fileHash
                : imported.fileHash,
            updatedAt: now,
            lastOpenedAt: now,
          );

    await databaseRegistryRepository.upsert(recordToSave);
    await databaseRegistryRepository.setActive(recordToSave.databaseId);
    await localDataSource.cacheDatabasePath(recordToSave.canonicalPath);

    if (clearCredentials) {
      await localDataSource.cacheKeyFilePath(null);
      await secureDataSource.clearMasterPassword();
      await appleAutofillV2Coordinator.clearCredentials();
    }

    return DatabaseSelectionSessionResult(
      status: DatabaseSessionStatus.success,
      path: recordToSave.canonicalPath,
      recentDatabasePaths: await _loadRecentDatabasePaths(),
      message: _buildDuplicateMessage(
        dedup: dedup,
        duplicateResolution: duplicateResolution,
      ),
    );
  }

  String? _buildDuplicateMessage({
    required DatabaseDedupResult dedup,
    required DatabaseDuplicateResolution? duplicateResolution,
  }) {
    if (!dedup.hasDuplicate) {
      return null;
    }
    return switch (duplicateResolution) {
      DatabaseDuplicateResolution.keepBoth =>
        'Duplicate detected. Kept both databases as requested.',
      DatabaseDuplicateResolution.replaceExisting =>
        'Duplicate detected. Existing database metadata was updated with the selected file.',
      _ => 'Existing database reused to avoid duplicates.',
    };
  }

  @override
  Future<DatabaseSelectionSessionResult> resolveDuplicateDecision({
    required DatabaseDuplicatePrompt duplicatePrompt,
    required DatabaseDuplicateResolution decision,
  }) async {
    final stagedImport = duplicatePrompt.stagedImport;
    if (stagedImport != null) {
      return _commitStagedImport(
        staged: stagedImport,
        overwriteExisting:
            decision == DatabaseDuplicateResolution.replaceExisting,
        decision: decision,
        duplicateRecord: duplicatePrompt.existingRecord,
      );
    }

    final result = await _applyImportedDatabase(
      duplicatePrompt.imported,
      clearCredentials: duplicatePrompt.clearCredentials,
      duplicateResolution: decision,
    );

    if (result.status == DatabaseSessionStatus.success &&
        duplicatePrompt.imported.sourceType == DatabaseSourceType.drive &&
        duplicatePrompt.imported.sourceRef != null &&
        result.path != null) {
      try {
        await databaseSyncRepository.linkDatabaseToDrive(
          databasePath: result.path!,
          remoteFileId: duplicatePrompt.imported.sourceRef!,
        );
      } catch (e, st) {
        logWarning('Drive linking failed after duplicate resolution.', e, st);
        return DatabaseSelectionSessionResult(
          status: DatabaseSessionStatus.success,
          path: result.path,
          recentDatabasePaths: result.recentDatabasePaths,
          promptBiometricSetup: true,
          message:
              'Database opened, but auto-link to Drive failed. You can link it from the Vault sync menu.',
        );
      }
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.success,
        path: result.path,
        recentDatabasePaths: result.recentDatabasePaths,
        promptBiometricSetup: true,
        message: result.message,
      );
    }

    return result;
  }

  Future<List<String>> _loadRecentDatabasePaths() async {
    if (_usesManagedStorage) {
      try {
        final entries = await MobileFileStorage.listFilesInAppDirectory(
          subdirectory: 'databases',
        );
        return entries
            .where((entry) => entry.name.toLowerCase().endsWith('.kdbx'))
            .map((entry) => entry.path)
            .toList(growable: false);
      } catch (e, st) {
        logWarning(
          'Unable to load recent database files from app storage.',
          e,
          st,
        );
        return const [];
      }
    }

    try {
      final records = await databaseRegistryRepository.list();
      if (records.isNotEmpty) {
        final sorted = [...records]
          ..sort((a, b) {
            final left =
                a.lastOpenedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final right =
                b.lastOpenedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return right.compareTo(left);
          });
        return sorted
            .map((record) => record.canonicalPath)
            .toList(growable: false);
      }
      return const [];
    } catch (e, st) {
      logWarning('Unable to load recent database list.', e, st);
      return const [];
    }
  }

  Future<String?> _resolveOutputFilePath(String preferredFileName) async {
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

  Future<String?> _prepareKeyFilePath({
    required String? keyFilePath,
    required bool generateKeyFile,
    required String? generatedKeyFilePath,
  }) async {
    if (!generateKeyFile) {
      if (keyFilePath == null || keyFilePath.trim().isEmpty) {
        return null;
      }
      if (_usesManagedStorage) {
        return databaseImportService.saveKeyFile(
          fileName: 'database.key',
          keyFileBytes: Uint8List(0),
          selectedPath: keyFilePath,
        );
      }
      return keyFilePath;
    }

    final keyBytes = _generateRandomKeyFileBytes();
    final fileName = generatedKeyFilePath == null
        ? 'database.key'
        : p.basename(generatedKeyFilePath);
    return databaseImportService.saveKeyFile(
      fileName: fileName,
      keyFileBytes: keyBytes,
      selectedPath: generatedKeyFilePath,
    );
  }

  Uint8List _generateRandomKeyFileBytes() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(64, (_) => random.nextInt(256)),
    );
  }

  Future<void> _saveSecurityProfile({
    required String path,
    required String? keyFilePath,
    required bool? biometricProtectionEnabled,
  }) async {
    final record = await _findRecordByPath(path);
    if (record == null) {
      return;
    }
    final existing = await databaseSecurityRepository.getProfile(
      record.databaseId,
    );
    final profile =
        (existing ??
                DatabaseSecurityProfile(
                  databaseId: record.databaseId,
                  biometricProtectionEnabled: true,
                ))
            .copyWith(
              keyFilePath: keyFilePath,
              biometricProtectionEnabled:
                  biometricProtectionEnabled ??
                  existing?.biometricProtectionEnabled,
              updatedAt: DateTime.now(),
              clearKeyFilePath: keyFilePath == null,
            );
    await databaseSecurityRepository.saveProfile(profile);
  }

  Future<void> _removeRecordByPath(String path) async {
    final record = await _findRecordByPath(path);
    if (record == null) {
      return;
    }
    await databaseSecurityRepository.removeProfile(record.databaseId);
    await databaseRegistryRepository.remove(record.databaseId);
  }

  Future<DatabaseRecord?> _findRecordByPath(String path) async {
    final records = await databaseRegistryRepository.list();
    for (final record in records) {
      if (_containsPath([record.canonicalPath], path)) {
        return record;
      }
    }
    return null;
  }

  Future<String> _hashFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return md5.convert(bytes).toString();
  }

  String _buildCreationMessage({
    required String databasePath,
    required String? keyFilePath,
  }) {
    final databaseMessage = _usesManagedStorage
        ? 'Database saved in app internal storage.'
        : 'Database saved to: $databasePath';
    final keyMessage = keyFilePath == null || keyFilePath.trim().isEmpty
        ? 'No key file configured.'
        : _usesManagedStorage
        ? 'Key file saved in app internal storage.'
        : 'Key file path: $keyFilePath';
    return '$databaseMessage $keyMessage';
  }

  String _generateDatabaseId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final random = Random.secure().nextInt(1 << 32).toRadixString(16);
    return 'db_$now$random';
  }

  bool get _usesManagedStorage => !kIsWeb;

  String? _normalizeKeyFilePath(String? keyFilePath) {
    final trimmed = keyFilePath?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  bool _sameKeyFilePath(String? left, String? right) {
    final normalizedLeft = _normalizeKeyFilePath(left);
    final normalizedRight = _normalizeKeyFilePath(right);
    if (normalizedLeft == null || normalizedRight == null) {
      return normalizedLeft == normalizedRight;
    }
    return p.equals(p.normalize(normalizedLeft), p.normalize(normalizedRight));
  }

  Future<bool> _keyFileExists(String keyFilePath) async {
    try {
      return await File(keyFilePath).exists();
    } catch (_) {
      return false;
    }
  }

  Future<String?> _ensureManagedKeyFilePath(String? keyFilePath) async {
    final normalized = _normalizeKeyFilePath(keyFilePath);
    if (normalized == null || !_usesManagedStorage) {
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

      return databaseImportService.saveKeyFile(
        fileName: p.basename(normalized),
        keyFileBytes: Uint8List(0),
        selectedPath: normalized,
      );
    } catch (_) {
      return normalized;
    }
  }
}
