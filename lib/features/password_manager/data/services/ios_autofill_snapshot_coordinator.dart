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

  bool get _isSupportedPlatform {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.iOS;
  }
}
