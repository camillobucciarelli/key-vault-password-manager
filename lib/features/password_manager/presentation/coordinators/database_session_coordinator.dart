import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:kdbx/kdbx.dart';
import 'package:loggy/loggy.dart';
import 'package:path/path.dart' as p;

import '../../../../core/utils/mobile_file_storage.dart';
import '../../data/datasources/secure_data_source.dart';
import '../../data/services/database_import_service.dart';
import '../../domain/entities/database_record.dart';
import '../../domain/entities/database_security_profile.dart';
import '../../domain/models/database_dedup_result.dart';
import '../../domain/models/database_import_result.dart';
import '../../domain/repositories/database_sync_repository.dart';
import '../../domain/usecases/get_active_database_usecase.dart';
import '../../domain/usecases/get_database_security_profile_usecase.dart';
import '../../domain/usecases/get_registered_databases_usecase.dart';
import '../../domain/usecases/get_selected_key_file_path_usecase.dart';
import '../../domain/usecases/link_database_to_drive_usecase.dart';
import '../../domain/usecases/remove_database_record_usecase.dart';
import '../../domain/usecases/resolve_database_duplicate_usecase.dart';
import '../../domain/usecases/save_database_security_profile_usecase.dart';
import '../../domain/usecases/save_selected_database_path_usecase.dart';
import '../../domain/usecases/save_selected_key_file_path_usecase.dart';
import '../../domain/usecases/set_active_database_usecase.dart';
import '../../domain/usecases/unlock_database_usecase.dart';
import '../../domain/usecases/upsert_database_record_usecase.dart';
import '../bloc/database_selection/database_selection_event.dart';

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
  });

  final DatabaseImportResult imported;
  final DatabaseRecord existingRecord;
  final bool clearCredentials;
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

  Future<DatabaseSelectionSessionResult> selectDriveDatabaseLocalCopy({
    required String localPath,
    required String remoteFileId,
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
}

class DatabaseSessionCoordinator implements DatabaseSessionCoordinatorContract {
  DatabaseSessionCoordinator({
    required this.saveSelectedDatabasePathUseCase,
    required this.getActiveDatabaseUseCase,
    required this.saveSelectedKeyFilePathUseCase,
    required this.getSelectedKeyFilePathUseCase,
    required this.secureDataSource,
    required this.databaseImportService,
    required this.resolveDatabaseDuplicateUseCase,
    required this.upsertDatabaseRecordUseCase,
    required this.removeDatabaseRecordUseCase,
    required this.setActiveDatabaseUseCase,
    required this.getRegisteredDatabasesUseCase,
    required this.linkDatabaseToDriveUseCase,
    required this.databaseSyncRepository,
    required this.getDatabaseSecurityProfileUseCase,
    required this.saveDatabaseSecurityProfileUseCase,
    required this.unlockDatabaseUseCase,
  });

  final SaveSelectedDatabasePathUseCase saveSelectedDatabasePathUseCase;
  final GetActiveDatabaseUseCase getActiveDatabaseUseCase;
  final SaveSelectedKeyFilePathUseCase saveSelectedKeyFilePathUseCase;
  final GetSelectedKeyFilePathUseCase getSelectedKeyFilePathUseCase;
  final SecureDataSource secureDataSource;
  final DatabaseImportService databaseImportService;
  final ResolveDatabaseDuplicateUseCase resolveDatabaseDuplicateUseCase;
  final UpsertDatabaseRecordUseCase upsertDatabaseRecordUseCase;
  final RemoveDatabaseRecordUseCase removeDatabaseRecordUseCase;
  final SetActiveDatabaseUseCase setActiveDatabaseUseCase;
  final GetRegisteredDatabasesUseCase getRegisteredDatabasesUseCase;
  final LinkDatabaseToDriveUseCase linkDatabaseToDriveUseCase;
  final DatabaseSyncRepository databaseSyncRepository;
  final GetDatabaseSecurityProfileUseCase getDatabaseSecurityProfileUseCase;
  final SaveDatabaseSecurityProfileUseCase saveDatabaseSecurityProfileUseCase;
  final UnlockDatabaseUseCase unlockDatabaseUseCase;

  @override
  Future<DatabaseSelectionSessionResult> checkInitialDatabase() async {
    final recent = await _loadRecentDatabasePaths();
    if (recent.length > 1) {
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.unselected,
        recentDatabasePaths: recent,
      );
    }

    final activeRecord = await getActiveDatabaseUseCase();
    final path =
        activeRecord?.canonicalPath ??
        (recent.length == 1 ? recent.first : null);

    if (path == null || path.isEmpty) {
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.unselected,
        recentDatabasePaths: recent,
      );
    }

    try {
      return _applyImportedDatabase(
        DatabaseImportResult(
          path: path,
          fileName: p.basename(path),
          fileHash: '',
          sourceType: DatabaseSourceType.local,
        ),
        clearCredentials: false,
        skipDedupWhenHashMissing: true,
      );
    } catch (e) {
      final updatedRecent = await _loadRecentDatabasePaths();
      return DatabaseSelectionSessionResult(
        status: DatabaseSessionStatus.error,
        message: 'Database file not found or corrupted.',
        recentDatabasePaths: updatedRecent,
      );
    }
  }

  @override
  Future<DatabaseSelectionSessionResult> selectExistingDatabase({
    required String fileName,
    String? selectedPath,
    List<int>? selectedBytes,
    bool overwriteExisting = false,
  }) async {
    final imported = await databaseImportService.importFromSelection(
      fileName: fileName,
      selectedPath: selectedPath,
      selectedBytes: selectedBytes,
      overwriteExisting: overwriteExisting,
    );

    return _applyImportedDatabase(imported, clearCredentials: true);
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

    final imported = await databaseImportService.openExistingPath(trimmed);
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

    await upsertDatabaseRecordUseCase(recordToSave);
    await setActiveDatabaseUseCase(recordToSave.databaseId);
    await saveSelectedDatabasePathUseCase(recordToSave.canonicalPath);
    await saveSelectedKeyFilePathUseCase(null);
    await secureDataSource.clearMasterPassword();

    return DatabaseSelectionSessionResult(
      status: DatabaseSessionStatus.success,
      path: recordToSave.canonicalPath,
      recentDatabasePaths: await _loadRecentDatabasePaths(),
    );
  }

  @override
  Future<DatabaseSelectionSessionResult> selectDriveDatabaseLocalCopy({
    required String localPath,
    required String remoteFileId,
  }) async {
    final imported = await databaseImportService.importDriveLocalCopy(
      localPath: localPath,
      remoteFileId: remoteFileId,
    );

    final result = await _applyImportedDatabase(
      imported,
      clearCredentials: true,
    );

    if (result.status == DatabaseSessionStatus.success && result.path != null) {
      try {
        await linkDatabaseToDriveUseCase(
          databasePath: result.path!,
          remoteFileId: remoteFileId,
        );
      } catch (e, st) {
        logWarning('Drive linking failed after download.', e, st);
        return DatabaseSelectionSessionResult(
          status: DatabaseSessionStatus.success,
          path: result.path,
          recentDatabasePaths: result.recentDatabasePaths,
          promptBiometricSetup: true,
          message:
              'Database opened, but auto-link to Drive failed. You can link it from the Vault sync menu.',
        );
      }
    }

    return DatabaseSelectionSessionResult(
      status: result.status,
      path: result.path,
      recentDatabasePaths: result.recentDatabasePaths,
      message: result.message,
      promptBiometricSetup: true,
    );
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
      await saveSelectedKeyFilePathUseCase(selectedKeyFilePath);
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
    if (activeRecord?.canonicalPath.trim() == trimmed) {
      await saveSelectedDatabasePathUseCase('');
      await saveSelectedKeyFilePathUseCase(null);
      await secureDataSource.clearMasterPassword();
      await setActiveDatabaseUseCase(null);
    }

    await _removeRecordByPath(trimmed);
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
        : await getDatabaseSecurityProfileUseCase(record.databaseId);

    final profileKeyFilePath = _normalizeKeyFilePath(profile?.keyFilePath);
    var keyFilePath = profileKeyFilePath;
    var profileKeyFileWasMissing = false;

    if (profileKeyFilePath != null &&
        !await _keyFileExists(profileKeyFilePath)) {
      keyFilePath = null;
      profileKeyFileWasMissing = true;
    }

    final cachedKeyFilePath = _normalizeKeyFilePath(
      await getSelectedKeyFilePathUseCase(),
    );
    var cachedKeyFileWasMissing = false;
    if (keyFilePath == null && cachedKeyFilePath != null) {
      if (await _keyFileExists(cachedKeyFilePath)) {
        keyFilePath = cachedKeyFilePath;
      } else {
        cachedKeyFileWasMissing = true;
      }
    }

    if (profileKeyFileWasMissing || cachedKeyFileWasMissing) {
      await saveSelectedKeyFilePathUseCase(keyFilePath);
      if (record != null) {
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

    await saveSelectedKeyFilePathUseCase(persistedKeyFilePath);
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
    final existing = await getDatabaseSecurityProfileUseCase(record.databaseId);
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
    await saveDatabaseSecurityProfileUseCase(profile);
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
    await saveSelectedKeyFilePathUseCase(persistedKeyFilePath);
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
    return value != null && value.trim().isNotEmpty;
  }

  Future<DatabaseSelectionSessionResult> _applyImportedDatabase(
    DatabaseImportResult imported, {
    required bool clearCredentials,
    bool skipDedupWhenHashMissing = false,
    DatabaseDuplicateResolution? duplicateResolution,
  }) async {
    final dedup = (skipDedupWhenHashMissing && imported.fileHash.trim().isEmpty)
        ? DatabaseDedupResult.noDuplicate
        : await resolveDatabaseDuplicateUseCase(
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

    final selectedRecord =
        (!dedup.hasDuplicate ||
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

    final recordToSave = selectedRecord.copyWith(
      canonicalPath: imported.path,
      displayName: imported.fileName,
      sourceType: imported.sourceType,
      sourceRef: imported.sourceRef,
      fileHash: imported.fileHash.isEmpty
          ? selectedRecord.fileHash
          : imported.fileHash,
      updatedAt: DateTime.now(),
      lastOpenedAt: DateTime.now(),
    );

    await upsertDatabaseRecordUseCase(recordToSave);
    await setActiveDatabaseUseCase(recordToSave.databaseId);
    await saveSelectedDatabasePathUseCase(recordToSave.canonicalPath);

    if (clearCredentials) {
      await saveSelectedKeyFilePathUseCase(null);
      await secureDataSource.clearMasterPassword();
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
        await linkDatabaseToDriveUseCase(
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
      final records = await getRegisteredDatabasesUseCase();
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
    final existing = await getDatabaseSecurityProfileUseCase(record.databaseId);
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
    await saveDatabaseSecurityProfileUseCase(profile);
  }

  Future<void> _removeRecordByPath(String path) async {
    final record = await _findRecordByPath(path);
    if (record == null) {
      return;
    }
    await removeDatabaseRecordUseCase(record.databaseId);
  }

  Future<DatabaseRecord?> _findRecordByPath(String path) async {
    final records = await getRegisteredDatabasesUseCase();
    for (final record in records) {
      if (record.canonicalPath.trim() == path.trim()) {
        return record;
      }
    }
    return null;
  }

  Future<String> _hashFile(String path) async {
    final bytes = await File(path).readAsBytes();
    var hash = 0;
    for (final value in bytes) {
      hash = 0x1fffffff & (hash + value);
    }
    return hash.toRadixString(16);
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
