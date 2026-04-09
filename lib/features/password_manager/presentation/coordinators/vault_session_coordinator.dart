import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../data/datasources/secure_data_source.dart';
import '../../data/services/vault_kdbx_service.dart';
import '../../domain/entities/database_security_profile.dart';
import '../../domain/repositories/database_sync_repository.dart';
import '../../domain/usecases/get_database_security_profile_usecase.dart';
import '../../domain/usecases/get_registered_databases_usecase.dart';
import '../../domain/usecases/save_database_security_profile_usecase.dart';
import '../../domain/usecases/save_selected_database_path_usecase.dart';
import '../../domain/usecases/save_selected_key_file_path_usecase.dart';
import '../../domain/usecases/set_active_database_usecase.dart';
import '../../domain/usecases/upsert_database_record_usecase.dart';
import '../../../../core/utils/mobile_file_storage.dart';

class DatabaseSettingsUpdateRequest {
  const DatabaseSettingsUpdateRequest({
    required this.currentDatabasePath,
    required this.fileName,
    required this.keyFilePath,
    required this.biometricProtectionEnabled,
    required this.changePassword,
    required this.inactivityLockTimeoutSeconds,
    this.currentPassword,
    this.newPassword,
  });

  final String currentDatabasePath;
  final String fileName;
  final String? keyFilePath;
  final bool biometricProtectionEnabled;
  final bool changePassword;
  final int? inactivityLockTimeoutSeconds;
  final String? currentPassword;
  final String? newPassword;
}

class DatabaseSettingsUpdateResult {
  const DatabaseSettingsUpdateResult({
    required this.databasePath,
    required this.passwordChanged,
  });

  final String databasePath;
  final bool passwordChanged;
}

class VaultSessionCoordinator {
  VaultSessionCoordinator({
    required this.saveSelectedDatabasePathUseCase,
    required this.saveSelectedKeyFilePathUseCase,
    required this.setActiveDatabaseUseCase,
    required this.secureDataSource,
    required this.getRegisteredDatabasesUseCase,
    required this.upsertDatabaseRecordUseCase,
    required this.databaseSyncRepository,
    required this.getDatabaseSecurityProfileUseCase,
    required this.saveDatabaseSecurityProfileUseCase,
    required this.vaultKdbxService,
  });

  final SaveSelectedDatabasePathUseCase saveSelectedDatabasePathUseCase;
  final SaveSelectedKeyFilePathUseCase saveSelectedKeyFilePathUseCase;
  final SetActiveDatabaseUseCase setActiveDatabaseUseCase;
  final SecureDataSource secureDataSource;
  final GetRegisteredDatabasesUseCase getRegisteredDatabasesUseCase;
  final UpsertDatabaseRecordUseCase upsertDatabaseRecordUseCase;
  final DatabaseSyncRepository databaseSyncRepository;
  final GetDatabaseSecurityProfileUseCase getDatabaseSecurityProfileUseCase;
  final SaveDatabaseSecurityProfileUseCase saveDatabaseSecurityProfileUseCase;
  final VaultKdbxService vaultKdbxService;

  Future<void> changeDatabase({required String currentDatabasePath}) async {
    await saveSelectedDatabasePathUseCase('');
    await saveSelectedKeyFilePathUseCase(null);
    await secureDataSource.clearMasterPassword();
    await setActiveDatabaseUseCase(null);
  }

  Future<void> lockVault({required String currentDatabasePath}) async {
    await saveSelectedDatabasePathUseCase(currentDatabasePath);
    await secureDataSource.clearMasterPassword();
  }

  Future<bool> getBiometricProtectionEnabledForPath({
    required String databasePath,
  }) async {
    if (databasePath.trim().isEmpty) {
      return false;
    }

    final records = await getRegisteredDatabasesUseCase();
    for (final record in records) {
      if (record.canonicalPath != databasePath) {
        continue;
      }
      final profile = await getDatabaseSecurityProfileUseCase(
        record.databaseId,
      );
      return profile?.biometricProtectionEnabled ?? false;
    }
    return false;
  }

  Future<int?> getInactivityLockTimeoutForPath({
    required String databasePath,
  }) async {
    if (databasePath.trim().isEmpty) {
      return null;
    }

    final records = await getRegisteredDatabasesUseCase();
    for (final record in records) {
      if (record.canonicalPath != databasePath) {
        continue;
      }
      final profile = await getDatabaseSecurityProfileUseCase(
        record.databaseId,
      );
      return profile?.inactivityLockTimeoutSeconds;
    }
    return null;
  }

  Future<DatabaseSettingsUpdateResult> updateDatabaseSettings(
    DatabaseSettingsUpdateRequest request,
  ) async {
    final normalizedName = _normalizeFileName(request.fileName);
    final normalizedKeyFilePath = _normalizeKeyFilePath(request.keyFilePath);
    if (normalizedKeyFilePath != null &&
        !await _keyFileExists(normalizedKeyFilePath)) {
      throw Exception('Selected key file not found. Please choose it again.');
    }
    final persistedKeyFilePath = await _ensureManagedKeyFilePath(
      normalizedKeyFilePath,
    );
    final currentPath = request.currentDatabasePath;
    final parentDir = p.dirname(currentPath);
    final targetPath = p.join(parentDir, normalizedName);

    if (targetPath != currentPath) {
      final targetFile = File(targetPath);
      if (await targetFile.exists()) {
        throw Exception('A database file with this name already exists.');
      }
    }

    var passwordChanged = false;
    if (request.changePassword) {
      final currentPassword = request.currentPassword ?? '';
      final newPassword = request.newPassword ?? '';
      if (currentPassword.trim().isEmpty || newPassword.trim().isEmpty) {
        throw Exception('Current and new password are required.');
      }
      await vaultKdbxService.changeMasterPassword(
        databasePath: currentPath,
        currentPassword: currentPassword,
        keyFilePath: persistedKeyFilePath,
        newPassword: newPassword,
      );
      await secureDataSource.saveMasterPassword(newPassword);
      passwordChanged = true;
    }

    var effectivePath = currentPath;
    if (targetPath != currentPath) {
      final currentFile = File(currentPath);
      if (!await currentFile.exists()) {
        throw Exception('Current database file not found.');
      }
      await currentFile.rename(targetPath);
      effectivePath = targetPath;
      await databaseSyncRepository.moveMappingPath(
        fromDatabasePath: currentPath,
        toDatabasePath: effectivePath,
      );
    }

    final records = await getRegisteredDatabasesUseCase();
    for (final record in records) {
      if (record.canonicalPath == currentPath) {
        await upsertDatabaseRecordUseCase(
          record.copyWith(
            canonicalPath: effectivePath,
            displayName: p.basename(effectivePath),
            updatedAt: DateTime.now(),
            lastOpenedAt: DateTime.now(),
          ),
        );

        final existingProfile = await getDatabaseSecurityProfileUseCase(
          record.databaseId,
        );
        final profile =
            (existingProfile ??
                    DatabaseSecurityProfile(databaseId: record.databaseId))
                .copyWith(
                  keyFilePath: persistedKeyFilePath,
                  biometricProtectionEnabled:
                      request.biometricProtectionEnabled,
                  inactivityLockTimeoutSeconds:
                      request.inactivityLockTimeoutSeconds,
                  updatedAt: DateTime.now(),
                  clearKeyFilePath: persistedKeyFilePath == null,
                  clearInactivityTimeout:
                      request.inactivityLockTimeoutSeconds == null,
                );
        await saveDatabaseSecurityProfileUseCase(profile);
        break;
      }
    }

    await saveSelectedDatabasePathUseCase(effectivePath);
    await saveSelectedKeyFilePathUseCase(persistedKeyFilePath);

    return DatabaseSettingsUpdateResult(
      databasePath: effectivePath,
      passwordChanged: passwordChanged,
    );
  }

  String _normalizeFileName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw Exception('Database file name is required.');
    }
    if (trimmed.contains(RegExp(r'[\\/:*?"<>|]'))) {
      throw Exception('Invalid characters in file name.');
    }
    return trimmed.toLowerCase().endsWith('.kdbx') ? trimmed : '$trimmed.kdbx';
  }

  String? _normalizeKeyFilePath(String? value) {
    final trimmed = value?.trim();
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
    if (normalized == null) {
      return null;
    }
    try {
      final alreadyManaged = await MobileFileStorage.isPathInAppDirectory(
        filePath: normalized,
        subdirectory: 'keys',
      );
      if (alreadyManaged) {
        return normalized;
      }

      final keyBytes = await File(normalized).readAsBytes();
      return MobileFileStorage.saveBytesToAppDirectory(
        bytes: Uint8List.fromList(keyBytes),
        fileName: p.basename(normalized),
        subdirectory: 'keys',
      );
    } catch (_) {
      return normalized;
    }
  }
}
