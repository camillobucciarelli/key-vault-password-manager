import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_autofill_service/flutter_autofill_service.dart';
import 'package:loggy/loggy.dart';

import '../../domain/services/vault_autofill_matcher.dart';
import '../../domain/usecases/get_selected_database_path_usecase.dart';
import '../../domain/usecases/get_selected_key_file_path_usecase.dart';
import '../datasources/secure_data_source.dart';
import 'vault_kdbx_service.dart';

class AndroidAutofillCoordinator with WidgetsBindingObserver {
  AndroidAutofillCoordinator({
    required this.autofillService,
    required this.getSelectedDatabasePathUseCase,
    required this.getSelectedKeyFilePathUseCase,
    required this.secureDataSource,
    required this.vaultKdbxService,
    required this.matcher,
  });

  final AutofillService autofillService;
  final GetSelectedDatabasePathUseCase getSelectedDatabasePathUseCase;
  final GetSelectedKeyFilePathUseCase getSelectedKeyFilePathUseCase;
  final SecureDataSource secureDataSource;
  final VaultKdbxService vaultKdbxService;
  final VaultAutofillMatcher matcher;

  bool _initialized = false;
  bool _processing = false;

  Future<void> initialize() async {
    if (_initialized || !_isSupportedPlatform) {
      return;
    }

    _initialized = true;
    WidgetsBinding.instance.addObserver(this);

    try {
      await autofillService.setPreferences(
        AutofillPreferences(enableDebug: false, enableSaving: true),
      );
      await handlePendingRequest();
    } catch (e, st) {
      logError('Unable to initialize Android autofill coordinator.', e, st);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      handlePendingRequest();
    }
  }

  Future<void> handlePendingRequest() async {
    if (!_initialized || _processing || !_isSupportedPlatform) {
      return;
    }

    _processing = true;
    try {
      final status = await autofillService.status;
      if (status != AutofillServiceStatus.enabled) {
        return;
      }

      final hasFillRequest =
          await autofillService.fillRequestedAutomatic ||
          await autofillService.fillRequestedInteractive;
      final metadata = await autofillService.autofillMetadata;

      if (hasFillRequest) {
        await _completeFillRequest(metadata);
      }

      if (metadata?.saveInfo != null) {
        await autofillService.onSaveComplete();
      }
    } catch (e, st) {
      logError('Unable to process Android autofill request.', e, st);
    } finally {
      _processing = false;
    }
  }

  bool get _isSupportedPlatform {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android;
  }

  Future<void> _completeFillRequest(AutofillMetadata? metadata) async {
    final databasePath = await getSelectedDatabasePathUseCase();
    if (databasePath == null || databasePath.trim().isEmpty) {
      await autofillService.resultWithDatasets(const []);
      return;
    }

    final password = await secureDataSource.getMasterPassword() ?? '';
    final keyFilePath = await getSelectedKeyFilePathUseCase();

    if (password.isEmpty && (keyFilePath == null || keyFilePath.isEmpty)) {
      await autofillService.resultWithDatasets(const []);
      return;
    }

    try {
      final entries = await vaultKdbxService.loadAllEntries(
        databasePath: databasePath,
        password: password,
        keyFilePath: keyFilePath,
      );

      final datasets = matcher
          .findBestMatches(
            entries: entries,
            packageNames: metadata?.packageNames ?? const {},
            webDomains:
                metadata?.webDomains
                    .map((webDomain) => webDomain.domain)
                    .toSet() ??
                const {},
          )
          .map(
            (entry) => PwDataset(
              label: _buildLabel(entry.title, entry.username),
              username: entry.username,
              password: entry.password,
            ),
          )
          .toList(growable: false);

      await autofillService.resultWithDatasets(datasets);
    } catch (e, st) {
      logError('Unable to build Android autofill dataset.', e, st);
      await autofillService.resultWithDatasets(const []);
    }
  }

  String _buildLabel(String title, String username) {
    final trimmedTitle = title.trim();
    final trimmedUsername = username.trim();
    if (trimmedTitle.isEmpty && trimmedUsername.isEmpty) {
      return 'Saved credential';
    }
    if (trimmedUsername.isEmpty) {
      return trimmedTitle;
    }
    if (trimmedTitle.isEmpty) {
      return trimmedUsername;
    }
    return '$trimmedTitle · $trimmedUsername';
  }
}
