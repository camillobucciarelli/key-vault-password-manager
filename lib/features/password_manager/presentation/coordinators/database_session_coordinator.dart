import 'dart:math';

import 'package:loggy/loggy.dart';
import 'package:path/path.dart' as p;

import '../../domain/entities/database_record.dart';
import '../../domain/entities/database_security_profile.dart';
import '../../domain/errors/database_access_failure.dart';
import '../../domain/models/create_database_step.dart';
import '../../domain/models/database_dedup_result.dart';
import '../../domain/models/database_import_result.dart';
import '../../domain/models/database_import_transaction.dart';
import '../../domain/models/database_selection_item.dart';
import '../../domain/models/drive_account_summary.dart';
import '../../domain/models/recent_database_removal_mode.dart';
import '../../domain/repositories/database_file_repository.dart';
import '../../domain/repositories/database_registry_repository.dart';
import '../../domain/repositories/database_security_repository.dart';
import '../../domain/repositories/database_session_repository.dart';
import '../../domain/repositories/database_sync_repository.dart';
import '../../domain/usecases/create_database_usecase.dart';
import '../../domain/usecases/get_active_database_usecase.dart';
import '../../domain/usecases/resolve_database_duplicate_usecase.dart';
import '../../domain/usecases/unlock_database_usecase.dart';
import 'apple_autofill_v2_coordinator.dart';
import 'session_secret_holder.dart';

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

/// C-1: replaces the former `List<String> recentDatabasePaths` with typed
/// [DatabaseSelectionItem]s built from registry/security/sync metadata plus
/// file existence — never from a directory listing, and never by decrypting
/// the vault.
class DatabaseSelectionSessionResult {
  const DatabaseSelectionSessionResult({
    required this.status,
    required this.items,
    this.path,
    this.message,
    this.promptBiometricSetup = false,
    this.duplicatePrompt,
  });

  final DatabaseSessionStatus status;
  final List<DatabaseSelectionItem> items;
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

/// C-7 coordinator: sequences multi-step selection/unlock/create workflows.
/// Depends only on domain ports/use cases and presentation coordinator
/// contracts — never on `data/`, `dart:io`, Flutter, `FilePicker`, `crypto`
/// or `kdbx`. `database_session_coordinator_imports_test.dart` enforces this
/// with an analyzer-based import-URI gate.
///
/// This is the single concrete coordinator (no `Contract` interface): BLoCs
/// depend on this class directly, and tests fake the domain ports/use cases
/// it is built from instead of faking the coordinator itself.
class DatabaseSessionCoordinator {
  DatabaseSessionCoordinator({
    required this.databaseFileRepository,
    required this.databaseSessionRepository,
    required this.databaseRegistryRepository,
    required this.databaseSecurityRepository,
    required this.databaseSyncRepository,
    required this.getActiveDatabaseUseCase,
    required this.resolveDatabaseDuplicateUseCase,
    required this.unlockDatabaseUseCase,
    required this.createDatabaseUseCase,
    required this.sessionSecretHolder,
    this.appleAutofillV2Coordinator = const NoopAppleAutofillV2Coordinator(),
  });

  final DatabaseFileRepository databaseFileRepository;
  final DatabaseSessionRepository databaseSessionRepository;
  final DatabaseRegistryRepository databaseRegistryRepository;
  final DatabaseSecurityRepository databaseSecurityRepository;
  final DatabaseSyncRepository databaseSyncRepository;
  final GetActiveDatabaseUseCase getActiveDatabaseUseCase;
  final ResolveDatabaseDuplicateUseCase resolveDatabaseDuplicateUseCase;
  final UnlockDatabaseUseCase unlockDatabaseUseCase;
  final CreateDatabaseUseCase createDatabaseUseCase;

  /// spec-011 FR-1: in-memory session secret. Slice 1 keeps every keystore
  /// write/read identical and only mirrors the secret here so `VaultBloc`
  /// no longer reads `SecureDataSource`.
  final SessionSecretHolder sessionSecretHolder;
  final AppleAutofillV2CoordinatorContract appleAutofillV2Coordinator;

  Future<DatabaseSelectionSessionResult> checkInitialDatabase() async {
    final items = await _loadSelectionItems();
    final activeRecord = await getActiveDatabaseUseCase();
    final activePath = activeRecord?.canonicalPath;
    final validActivePath =
        activePath != null && _itemsContainPath(items, activePath)
        ? activePath
        : null;

    if (items.length > 1 && validActivePath == null) {
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.unselected,
        items: items,
      );
    }

    final path = validActivePath ?? (items.length == 1 ? items.first.canonicalPath : null);

    if (path == null || path.isEmpty) {
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.unselected,
        items: items,
      );
    }

    // A registered-but-missing active database routes to the selection
    // list (FR-1 Locate), not a generic open failure: nothing was
    // corrupted, the file is simply absent.
    final resolvedItem = items.cast<DatabaseSelectionItem?>().firstWhere(
      (item) => item != null && _containsPath([item.canonicalPath], path),
      orElse: () => null,
    );
    if (resolvedItem != null && resolvedItem.isMissing) {
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.unselected,
        items: items,
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
      final updatedItems = await _loadSelectionItems();
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.error,
        message: 'Database file not found or corrupted.',
        items: updatedItems,
      );
    }
  }

  bool _containsPath(List<String> paths, String target) {
    final normalizedTarget = p.normalize(target.trim());
    return paths.any(
      (path) => p.equals(p.normalize(path.trim()), normalizedTarget),
    );
  }

  bool _itemsContainPath(List<DatabaseSelectionItem> items, String target) {
    return _containsPath(
      items.map((item) => item.canonicalPath).toList(growable: false),
      target,
    );
  }

  Future<DatabaseSelectionSessionResult> selectExistingDatabase({
    required String fileName,
    String? selectedPath,
    List<int>? selectedBytes,
    bool overwriteExisting = false,
  }) async {
    final staged = await databaseFileRepository.stageLocalSelection(
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
        items: await _loadSelectionItems(),
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

  Future<DatabaseSelectionSessionResult> openRecentDatabase(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.unselected,
        items: await _loadSelectionItems(),
      );
    }

    return _openExistingDatabase(trimmed, clearCredentials: true);
  }

  /// FR-1 Locate: only valid for a missing recent item. Requires a stored
  /// hash match when available; mismatch or invalid/corrupt selection
  /// mutates nothing (the thrown `DatabaseAccessFailure` propagates to the
  /// caller before any registry write).
  Future<DatabaseSelectionSessionResult> locateMissingDatabase({
    required String databaseId,
    required String selectedPath,
  }) async {
    final record = await databaseRegistryRepository.getById(databaseId);
    if (record == null) {
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.error,
        message: 'Database record not found.',
        items: await _loadSelectionItems(),
      );
    }

    final imported = await databaseFileRepository.openExistingPath(
      selectedPath,
    );

    final storedHash = record.fileHash;
    if (storedHash != null &&
        storedHash.isNotEmpty &&
        storedHash != imported.fileHash) {
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.error,
        message:
            'Selected file does not match the missing database. Use "Open existing database" instead.',
        items: await _loadSelectionItems(),
      );
    }

    final now = DateTime.now();
    final updatedRecord = record.copyWith(
      canonicalPath: imported.path,
      fileHash: imported.fileHash,
      updatedAt: now,
      lastOpenedAt: now,
    );
    await databaseRegistryRepository.upsert(updatedRecord);
    if (record.sourceType == DatabaseSourceType.drive) {
      try {
        await databaseSyncRepository.moveMappingPath(
          fromDatabasePath: record.canonicalPath,
          toDatabasePath: imported.path,
        );
      } catch (e, st) {
        logWarning('Unable to move sync mapping after Locate.', e, st);
      }
    }
    await databaseRegistryRepository.setActive(updatedRecord.databaseId);

    return DatabaseSelectionSessionResult(
      status: DatabaseSessionStatus.success,
      path: updatedRecord.canonicalPath,
      items: await _loadSelectionItems(),
    );
  }

  Future<DatabaseSelectionSessionResult> _openExistingDatabase(
    String path, {
    required bool clearCredentials,
  }) async {
    final imported = await databaseFileRepository.openExistingPath(path);
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
    if (clearCredentials) {
      sessionSecretHolder.clear();
      await databaseSessionRepository.cacheKeyFilePath(null);
      await databaseSessionRepository.clearMasterPassword();
      await appleAutofillV2Coordinator.clearCredentials();
    }

    return DatabaseSelectionSessionResult(
      status: DatabaseSessionStatus.success,
      path: recordToSave.canonicalPath,
      items: await _loadSelectionItems(),
    );
  }

  /// C-2: Drive files for the picker plus the connected account summary
  /// (mobile email, or the exact desktop fallback).
  Future<DrivePickerData> getDrivePickerData() async {
    if (!await databaseSyncRepository.isConnected()) {
      await databaseSyncRepository.connect();
    }
    final files = await databaseSyncRepository.listRemoteFiles();
    final account = await databaseSyncRepository.getConnectedAccount();
    return DrivePickerData(files: files, account: account);
  }

  Future<bool> hasManagedDatabaseNamed(String fileName) async {
    final path = await databaseFileRepository.managedDatabasePath(fileName);
    return databaseFileRepository.fileExists(path);
  }

  Future<DatabaseSelectionSessionResult> selectDriveDatabase({
    required String remoteFileId,
    required String remoteFileName,
    required bool overwriteExisting,
  }) async {
    final bytes = await databaseSyncRepository.downloadRemoteFile(remoteFileId);
    final staged = await databaseFileRepository.stageDriveDownload(
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
        items: await _loadSelectionItems(),
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
      await databaseFileRepository.discardStagedDatabase(staged);
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.unselected,
        items: await _loadSelectionItems(),
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
        await _clearSessionCredentials();
        final items = await _loadSelectionItems();
        if (staged.imported.sourceType == DatabaseSourceType.drive) {
          await databaseSyncRepository.linkDatabaseToDrive(
            databasePath: duplicateRecord.canonicalPath,
            remoteFileId: staged.imported.sourceRef,
          );
        }
        return DatabaseSelectionSessionResult(
          status: DatabaseSessionStatus.success,
          path: duplicateRecord.canonicalPath,
          items: items,
          promptBiometricSetup:
              staged.imported.sourceType == DatabaseSourceType.drive,
          message: 'Existing database reused to avoid duplicates.',
        );
      } finally {
        try {
          await databaseFileRepository.discardStagedDatabase(staged);
        } catch (_) {}
      }
    }

    String? targetPath;
    if (decision == DatabaseDuplicateResolution.replaceExisting &&
        duplicateRecord != null) {
      targetPath = duplicateRecord.canonicalPath;
    } else if (decision != DatabaseDuplicateResolution.keepBoth &&
        overwriteExisting) {
      targetPath = await databaseFileRepository.managedDatabasePath(
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
    final originalKeyFilePath = await databaseSessionRepository
        .getCachedKeyFilePath();
    final originalPassword = await databaseSessionRepository.getMasterPassword();
    final commit = await databaseFileRepository.commitStagedDatabase(
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
      await _clearSessionCredentials();
      final items = await _loadSelectionItems();
      if (staged.imported.sourceType == DatabaseSourceType.drive) {
        await databaseSyncRepository.linkDatabaseToDrive(
          databasePath: recordToSave.canonicalPath,
          remoteFileId: staged.imported.sourceRef,
        );
      }
      try {
        await databaseFileRepository.finalizeDatabaseCommit(commit);
      } catch (_) {
        // Database and metadata are committed. Keep bounded backup for recovery.
      }
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.success,
        path: recordToSave.canonicalPath,
        items: items,
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
        await databaseFileRepository.rollbackDatabaseCommit(commit);
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
        await databaseSessionRepository.cacheKeyFilePath(originalKeyFilePath);
        if (originalPassword == null) {
          sessionSecretHolder.clear();
          await databaseSessionRepository.clearMasterPassword();
        } else {
          sessionSecretHolder.set(originalPassword);
          await databaseSessionRepository.saveMasterPassword(originalPassword);
        }
      } catch (_) {}
      rethrow;
    }
  }

  Future<DatabaseSelectionSessionResult> createNewDatabase({
    required String databaseFileName,
    required String password,
    String? keyFilePath,
    required bool biometricProtectionEnabled,
    required bool generateKeyFile,
    String? generatedKeyFilePath,
  }) async {
    final created = await createDatabaseUseCase(
      CreateDatabaseRequest(
        databaseFileName: databaseFileName,
        password: password,
        keyFilePath: keyFilePath,
        generateKeyFile: generateKeyFile,
        generatedKeyFilePath: generatedKeyFilePath,
      ),
    );

    if (created == null) {
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.unselected,
        items: await _loadSelectionItems(),
      );
    }

    final imported = DatabaseImportResult(
      path: created.databasePath,
      fileName: p.basename(created.databasePath),
      fileHash: created.fileHash,
      sourceType: DatabaseSourceType.created,
    );
    final result = await _applyImportedDatabase(
      imported,
      clearCredentials: false,
    );

    if (result.path != null) {
      await _saveSecurityProfile(
        path: result.path!,
        keyFilePath: created.keyFilePath,
        biometricProtectionEnabled: biometricProtectionEnabled,
      );
      sessionSecretHolder.set(password);
      await databaseSessionRepository.saveMasterPassword(password);
      await databaseSessionRepository.cacheKeyFilePath(created.keyFilePath);
    }

    return DatabaseSelectionSessionResult(
      status: result.status,
      path: result.path,
      items: result.items,
      message: result.path == null ? result.message : 'Database created.',
    );
  }

  /// FR-2 create-flow step policy (C-5): pure decision, no I/O. Returns the
  /// next step, or `current` unchanged when the supplied validation facts do
  /// not allow advancing.
  CreateDatabaseStep resolveCreateDatabaseStepAdvance({
    required CreateDatabaseStep current,
    required bool fieldsNonEmpty,
    bool confirmationMatches = true,
  }) {
    if (!fieldsNonEmpty || !confirmationMatches) {
      return current;
    }
    return switch (current) {
      CreateDatabaseStep.nameAndStorage => CreateDatabaseStep.masterPassword,
      CreateDatabaseStep.masterPassword => CreateDatabaseStep.optionalLocks,
      CreateDatabaseStep.optionalLocks => CreateDatabaseStep.optionalLocks,
    };
  }

  CreateDatabaseStep resolveCreateDatabaseStepBack(CreateDatabaseStep current) {
    return switch (current) {
      CreateDatabaseStep.nameAndStorage => CreateDatabaseStep.nameAndStorage,
      CreateDatabaseStep.masterPassword => CreateDatabaseStep.nameAndStorage,
      CreateDatabaseStep.optionalLocks => CreateDatabaseStep.masterPassword,
    };
  }

  Future<DatabaseSelectionSessionResult> removeRecentDatabase({
    required String path,
    required RecentDatabaseRemovalMode mode,
  }) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.unselected,
        items: await _loadSelectionItems(),
      );
    }

    var userMessage = 'Database removed from recent list.';
    final activeRecord = await getActiveDatabaseUseCase();
    if (activeRecord != null &&
        _containsPath([activeRecord.canonicalPath], trimmed)) {
      sessionSecretHolder.clear();
      await databaseSessionRepository.cacheKeyFilePath(null);
      await databaseSessionRepository.clearMasterPassword();
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
      if (await databaseFileRepository.fileExists(trimmed)) {
        await databaseFileRepository.deleteFile(trimmed);
        userMessage = 'Database removed from list and file deleted.';
      } else {
        userMessage = 'Database removed from list. File was already missing.';
      }
    }

    return DatabaseSelectionSessionResult(
      status: DatabaseSessionStatus.info,
      message: userMessage,
      items: await _loadSelectionItems(),
    );
  }

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
        !await databaseFileRepository.keyFileExists(profileKeyFilePath)) {
      keyFilePath = null;
      profileKeyFileWasMissing = true;
    }

    final cachedKeyFilePath = _normalizeKeyFilePath(
      await databaseSessionRepository.getCachedKeyFilePath(),
    );
    var cachedKeyFileWasMissing = false;
    if (keyFilePath == null && record == null && cachedKeyFilePath != null) {
      if (await databaseFileRepository.keyFileExists(cachedKeyFilePath)) {
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
      await databaseSessionRepository.cacheKeyFilePath(keyFilePath);
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

  Future<void> updateKeyFilePath({
    required String databasePath,
    required String? keyFilePath,
  }) async {
    final normalizedKeyFilePath = _normalizeKeyFilePath(keyFilePath);
    if (normalizedKeyFilePath != null &&
        !await databaseFileRepository.keyFileExists(normalizedKeyFilePath)) {
      throw const KeyFileMissingFailure();
    }

    final persistedKeyFilePath = await databaseFileRepository
        .ensureManagedKeyFilePath(normalizedKeyFilePath);

    await databaseSessionRepository.cacheKeyFilePath(persistedKeyFilePath);
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

  Future<void> unlockWithManualCredentials({
    required String databasePath,
    required String password,
    required String? keyFilePath,
  }) async {
    final persistedKeyFilePath = await databaseFileRepository
        .ensureManagedKeyFilePath(keyFilePath);
    try {
      await unlockDatabaseUseCase(
        databasePath: databasePath,
        password: password,
        keyFilePath: persistedKeyFilePath,
      );
    } catch (_) {
      // spec-011 FR-2: unlock failure never leaves a stale session secret.
      sessionSecretHolder.clear();
      rethrow;
    }
    sessionSecretHolder.set(password);
    await databaseSessionRepository.cacheKeyFilePath(persistedKeyFilePath);
    await databaseSessionRepository.saveMasterPassword(password);
    await _saveSecurityProfile(
      path: databasePath,
      keyFilePath: persistedKeyFilePath,
      biometricProtectionEnabled: null,
    );
  }

  Future<void> unlockWithStoredCredentials({
    required String databasePath,
    required String? keyFilePath,
  }) async {
    final storedPassword = await databaseSessionRepository.getMasterPassword();
    // spec-011 FR-2: no silent empty-string fallback. An empty password is
    // only a deliberate credential when a key file is part of the unlock.
    if (storedPassword == null && keyFilePath == null) {
      sessionSecretHolder.clear();
      throw const InvalidCredentialsFailure();
    }
    final effectivePassword = storedPassword ?? '';
    try {
      await unlockDatabaseUseCase(
        databasePath: databasePath,
        password: effectivePassword,
        keyFilePath: keyFilePath,
      );
    } catch (_) {
      sessionSecretHolder.clear();
      rethrow;
    }
    sessionSecretHolder.set(effectivePassword);
  }

  Future<bool> hasStoredMasterPassword() async {
    final value = await databaseSessionRepository.getMasterPassword();
    return value != null && value.isNotEmpty;
  }

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
    sessionSecretHolder.clear();
    await databaseSessionRepository.cacheKeyFilePath(null);
    await databaseSessionRepository.clearMasterPassword();
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
        items: await _loadSelectionItems(),
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
        items: await _loadSelectionItems(),
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

    if (clearCredentials) {
      sessionSecretHolder.clear();
      await databaseSessionRepository.cacheKeyFilePath(null);
      await databaseSessionRepository.clearMasterPassword();
      await appleAutofillV2Coordinator.clearCredentials();
    }

    return DatabaseSelectionSessionResult(
      status: DatabaseSessionStatus.success,
      path: recordToSave.canonicalPath,
      items: await _loadSelectionItems(),
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
          items: result.items,
          promptBiometricSetup: true,
          message:
              'Database opened, but auto-link to Drive failed. You can link it from the Vault sync menu.',
        );
      }
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.success,
        path: result.path,
        items: result.items,
        promptBiometricSetup: true,
        message: result.message,
      );
    }

    return result;
  }

  /// C-1: builds selection metadata by joining registry/security/sync
  /// records with file existence once — never a directory listing, never a
  /// decrypted read.
  Future<List<DatabaseSelectionItem>> _loadSelectionItems() async {
    try {
      final records = await databaseRegistryRepository.list();
      final activeId = await databaseRegistryRepository.getActive();
      final items = <DatabaseSelectionItem>[];
      for (final record in records) {
        final profile = await databaseSecurityRepository.getProfile(
          record.databaseId,
        );
        final exists = await databaseFileRepository.fileExists(
          record.canonicalPath,
        );
        DateTime? lastSyncAt;
        String? lastSyncError;
        if (record.sourceType == DatabaseSourceType.drive) {
          try {
            final mapping = await databaseSyncRepository.getMapping(
              record.canonicalPath,
            );
            lastSyncAt = mapping?.lastSyncAt;
            lastSyncError = mapping?.lastError;
          } catch (_) {
            // Sync metadata is best-effort for the selection row; a
            // failure here must not block the selection list itself.
          }
        }
        final keyFilePath = profile?.keyFilePath;
        items.add(
          DatabaseSelectionItem(
            databaseId: record.databaseId,
            canonicalPath: record.canonicalPath,
            displayName: record.displayName,
            sourceType: record.sourceType,
            sourceRef: record.sourceRef,
            isActive: record.databaseId == activeId,
            isMissing: !exists,
            biometricProtectionEnabled:
                profile?.biometricProtectionEnabled ?? false,
            keyFileConfigured:
                keyFilePath != null && keyFilePath.trim().isNotEmpty,
            lastOpenedAt: record.lastOpenedAt,
            lastSyncAt: lastSyncAt,
            lastSyncError: lastSyncError,
          ),
        );
      }
      items.sort((a, b) {
        final left = a.lastOpenedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final right = b.lastOpenedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return right.compareTo(left);
      });
      return items;
    } catch (e, st) {
      logWarning('Unable to load database selection metadata.', e, st);
      return const [];
    }
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

  String _generateDatabaseId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final random = Random.secure().nextInt(1 << 32).toRadixString(16);
    return 'db_$now$random';
  }

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
}
