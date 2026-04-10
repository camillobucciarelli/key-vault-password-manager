import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:loggy/loggy.dart';

import '../../domain/usecases/get_active_database_usecase.dart';
import '../../domain/usecases/get_selected_key_file_path_usecase.dart';
import '../datasources/ios_autofill_data_source.dart';
import '../datasources/secure_data_source.dart';
import 'vault_kdbx_service.dart';

class IosAutofillSnapshotCoordinator with WidgetsBindingObserver {
  IosAutofillSnapshotCoordinator({
    required this.getActiveDatabaseUseCase,
    required this.getSelectedKeyFilePathUseCase,
    required this.secureDataSource,
    required this.vaultKdbxService,
    required this.iosAutofillDataSource,
  });

  final GetActiveDatabaseUseCase getActiveDatabaseUseCase;
  final GetSelectedKeyFilePathUseCase getSelectedKeyFilePathUseCase;
  final SecureDataSource secureDataSource;
  final VaultKdbxService vaultKdbxService;
  final IosAutofillDataSource iosAutofillDataSource;

  bool _initialized = false;
  bool _processing = false;

  Future<void> initialize() async {
    if (_initialized || !_isSupportedPlatform) {
      return;
    }

    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    await syncSnapshot();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      syncSnapshot();
    }
  }

  Future<void> syncSnapshot() async {
    if (!_initialized || _processing || !_isSupportedPlatform) {
      return;
    }

    _processing = true;
    try {
      await _processPendingSaves();   // process before refreshing snapshot

      final active = await getActiveDatabaseUseCase();
      final databasePath = active?.canonicalPath;
      if (databasePath == null || databasePath.trim().isEmpty) {
        await iosAutofillDataSource.clearSnapshot();
        return;
      }

      final password = await secureDataSource.getMasterPassword() ?? '';
      final keyFilePath = await getSelectedKeyFilePathUseCase();

      if (password.isEmpty && (keyFilePath == null || keyFilePath.isEmpty)) {
        await iosAutofillDataSource.clearSnapshot();
        return;
      }

      final entries = await vaultKdbxService.loadAllEntries(
        databasePath: databasePath,
        password: password,
        keyFilePath: keyFilePath,
      );

      await iosAutofillDataSource.saveSnapshot(entries);
    } catch (e, st) {
      logError('Unable to sync iOS autofill snapshot.', e, st);
    } finally {
      _processing = false;
    }
  }

  Future<void> _processPendingSaves() async {
    final pending = await iosAutofillDataSource.readAndClearPendingSaves();
    if (pending.isEmpty) return;

    final active = await getActiveDatabaseUseCase();
    final databasePath = active?.canonicalPath;
    if (databasePath == null || databasePath.trim().isEmpty) return;

    final password = await secureDataSource.getMasterPassword() ?? '';
    final keyFilePath = await getSelectedKeyFilePathUseCase();
    if (password.isEmpty && (keyFilePath == null || keyFilePath.isEmpty)) return;

    try {
      final vault = await vaultKdbxService.loadVault(
        databasePath: databasePath,
        password: password,
        keyFilePath: keyFilePath,
      );

      for (final save in pending) {
        final title = (save['title'] as String?) ?? '';
        final username = (save['username'] as String?) ?? '';
        final entryPassword = (save['password'] as String?) ?? '';
        final url = (save['url'] as String?) ?? '';

        if (username.isEmpty && entryPassword.isEmpty) continue;

        await vaultKdbxService.createEntry(
          databasePath: databasePath,
          password: password,
          keyFilePath: keyFilePath,
          groupId: vault.rootGroupId,
          title: title.isEmpty ? (url.isEmpty ? 'Saved credential' : url) : title,
          username: username,
          entryPassword: entryPassword,
          url: url,
          notes: '',
          customFields: const [],
        );
      }
    } catch (e, st) {
      logError('Failed to process pending iOS autofill saves.', e, st);
    }
  }

  bool get _isSupportedPlatform {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.iOS;
  }
}
