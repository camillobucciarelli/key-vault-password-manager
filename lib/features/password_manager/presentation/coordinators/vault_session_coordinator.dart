import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../data/datasources/local_data_source.dart';
import '../../data/datasources/secure_data_source.dart';
import '../../data/services/vault_kdbx_service.dart';
import '../../domain/entities/database_record.dart';
import '../../domain/entities/database_security_profile.dart';
import '../../domain/repositories/database_registry_repository.dart';
import '../../domain/repositories/database_security_repository.dart';
import '../../domain/repositories/database_sync_repository.dart';
import '../../../../core/utils/mobile_file_storage.dart';
import 'apple_autofill_v2_coordinator.dart';

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
    required this.localDataSource,
    required this.databaseRegistryRepository,
    required this.databaseSecurityRepository,
    required this.secureDataSource,
    required this.databaseSyncRepository,
    required this.vaultKdbxService,
    this.appleAutofillV2Coordinator = const NoopAppleAutofillV2Coordinator(),
  });

  final LocalDataSource localDataSource;
  final DatabaseRegistryRepository databaseRegistryRepository;
  final DatabaseSecurityRepository databaseSecurityRepository;
  final SecureDataSource secureDataSource;
  final DatabaseSyncRepository databaseSyncRepository;
  final VaultKdbxService vaultKdbxService;
  final AppleAutofillV2CoordinatorContract appleAutofillV2Coordinator;

  Future<String?> getSelectedKeyFilePath() {
    return localDataSource.getCachedKeyFilePath();
  }

  Future<String?> getPersistedKeyFilePath(String databasePath) async {
    final record = await _findRecordByPath(databasePath);
    if (record == null) {
      return localDataSource.getCachedKeyFilePath();
    }
    final profile = await databaseSecurityRepository.getProfile(
      record.databaseId,
    );
    return profile?.keyFilePath;
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

  Future<void> changeDatabase({required String currentDatabasePath}) async {
    await appleAutofillV2Coordinator.clearCredentials();
    await localDataSource.cacheDatabasePath('');
    await localDataSource.cacheKeyFilePath(null);
    await secureDataSource.clearMasterPassword();
    await databaseRegistryRepository.setActive(null);
  }

  Future<void> lockVault({required String currentDatabasePath}) async {
    await appleAutofillV2Coordinator.clearCredentials();
    await localDataSource.cacheDatabasePath(currentDatabasePath);
    await secureDataSource.clearMasterPassword();
  }

  Future<bool> getBiometricProtectionEnabledForPath({
    required String databasePath,
  }) async {
    if (databasePath.trim().isEmpty) {
      return false;
    }

    final records = await databaseRegistryRepository.list();
    for (final record in records) {
      if (record.canonicalPath != databasePath) {
        continue;
      }
      final profile = await databaseSecurityRepository.getProfile(
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

    final records = await databaseRegistryRepository.list();
    for (final record in records) {
      if (record.canonicalPath != databasePath) {
        continue;
      }
      final profile = await databaseSecurityRepository.getProfile(
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
    final records = await databaseRegistryRepository.list();
    final record = records
        .where((item) => item.canonicalPath == currentPath)
        .firstOrNull;
    if (record == null) {
      throw Exception('Current database is not registered.');
    }
    final existingProfile = await databaseSecurityRepository.getProfile(
      record.databaseId,
    );
    final currentKeyFilePath = _normalizeKeyFilePath(
      existingProfile?.keyFilePath ??
          await localDataSource.getCachedKeyFilePath(),
    );
    final keyFileChanged = !_samePath(currentKeyFilePath, persistedKeyFilePath);

    if (!p.equals(targetPath, currentPath)) {
      final targetFile = File(targetPath);
      if (await targetFile.exists()) {
        throw Exception('A database file with this name already exists.');
      }
    }

    final storedPassword = await secureDataSource.getMasterPassword();
    var currentPassword = storedPassword;
    var newPassword = storedPassword;
    if (request.changePassword || keyFileChanged) {
      currentPassword = request.changePassword
          ? request.currentPassword ?? ''
          : storedPassword;
      newPassword = request.changePassword
          ? request.newPassword ?? ''
          : storedPassword;
      if (currentPassword == null || newPassword == null) {
        throw Exception('Current vault credentials are unavailable.');
      }
      if (request.changePassword && newPassword.isEmpty) {
        throw Exception('New password is required.');
      }
      if (newPassword.isEmpty && persistedKeyFilePath == null) {
        throw Exception('At least one unlock credential is required.');
      }
    }

    var effectivePath = currentPath;
    var mappingMoved = false;
    if (!p.equals(targetPath, currentPath)) {
      final currentFile = File(currentPath);
      if (!await currentFile.exists()) {
        throw Exception('Current database file not found.');
      }
      await currentFile.rename(targetPath);
      effectivePath = targetPath;
      try {
        await databaseSyncRepository.moveMappingPath(
          fromDatabasePath: currentPath,
          toDatabasePath: effectivePath,
        );
        mappingMoved = true;
      } catch (_) {
        await File(effectivePath).rename(currentPath);
        rethrow;
      }
    }

    final profile =
        (existingProfile ??
                DatabaseSecurityProfile(databaseId: record.databaseId))
            .copyWith(
              keyFilePath: persistedKeyFilePath,
              biometricProtectionEnabled: request.biometricProtectionEnabled,
              inactivityLockTimeoutSeconds:
                  request.inactivityLockTimeoutSeconds,
              updatedAt: DateTime.now(),
              clearKeyFilePath: persistedKeyFilePath == null,
              clearInactivityTimeout:
                  request.inactivityLockTimeoutSeconds == null,
            );
    KdbxCredentialChange? credentialChange;
    try {
      if (request.changePassword || keyFileChanged) {
        credentialChange = await vaultKdbxService.beginCredentialChange(
          databasePath: effectivePath,
          currentPassword: currentPassword!,
          currentKeyFilePath: currentKeyFilePath,
          newPassword: newPassword!,
          newKeyFilePath: persistedKeyFilePath,
        );
      }

      if (request.changePassword) {
        await secureDataSource.saveMasterPassword(newPassword!);
      }
      await databaseRegistryRepository.upsert(
        record.copyWith(
          canonicalPath: effectivePath,
          displayName: p.basename(effectivePath),
          updatedAt: DateTime.now(),
          lastOpenedAt: DateTime.now(),
        ),
      );
      await databaseSecurityRepository.saveProfile(profile);
      await localDataSource.cacheDatabasePath(effectivePath);
      await localDataSource.cacheKeyFilePath(persistedKeyFilePath);

      if (credentialChange != null) {
        try {
          await vaultKdbxService.finalizeCredentialChange(credentialChange);
        } catch (_) {
          // Vault and metadata are committed. Keep bounded backup for recovery.
        }
      }
      return DatabaseSettingsUpdateResult(
        databasePath: effectivePath,
        passwordChanged: request.changePassword,
      );
    } catch (_) {
      if (credentialChange != null) {
        try {
          await vaultKdbxService.rollbackCredentialChange(credentialChange);
        } catch (_) {}
      }
      await _restoreSettingsMetadata(
        record: record,
        profile: existingProfile,
        databasePath: currentPath,
        keyFilePath: currentKeyFilePath,
        password: storedPassword,
      );
      if (mappingMoved) {
        try {
          await databaseSyncRepository.moveMappingPath(
            fromDatabasePath: effectivePath,
            toDatabasePath: currentPath,
          );
        } catch (_) {}
      }
      if (!p.equals(effectivePath, currentPath) &&
          await File(effectivePath).exists()) {
        try {
          await File(effectivePath).rename(currentPath);
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> _restoreSettingsMetadata({
    required DatabaseRecord record,
    required DatabaseSecurityProfile? profile,
    required String databasePath,
    required String? keyFilePath,
    required String? password,
  }) async {
    try {
      await databaseRegistryRepository.upsert(record);
    } catch (_) {}
    try {
      if (profile == null) {
        await databaseSecurityRepository.removeProfile(record.databaseId);
      } else {
        await databaseSecurityRepository.saveProfile(profile);
      }
    } catch (_) {}
    try {
      await localDataSource.cacheDatabasePath(databasePath);
    } catch (_) {}
    try {
      await localDataSource.cacheKeyFilePath(keyFilePath);
    } catch (_) {}
    try {
      if (password == null) {
        await secureDataSource.clearMasterPassword();
      } else {
        await secureDataSource.saveMasterPassword(password);
      }
    } catch (_) {}
  }

  Future<DatabaseRecord?> _findRecordByPath(String databasePath) async {
    for (final record in await databaseRegistryRepository.list()) {
      if (p.equals(
        p.normalize(record.canonicalPath),
        p.normalize(databasePath),
      )) {
        return record;
      }
    }
    return null;
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

  bool _samePath(String? left, String? right) {
    if (left == null || right == null) {
      return left == right;
    }
    return p.equals(p.normalize(left), p.normalize(right));
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
