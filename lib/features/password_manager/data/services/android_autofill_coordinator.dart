import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_autofill_service/flutter_autofill_service.dart';
import 'package:loggy/loggy.dart';

import '../../domain/models/vault_custom_field.dart';
import '../../domain/models/vault_entry.dart';
import '../../domain/services/password_generator_service.dart';
import '../../domain/services/vault_autofill_matcher.dart';
import '../../domain/usecases/get_active_database_usecase.dart';
import '../../domain/usecases/get_selected_key_file_path_usecase.dart';
import '../datasources/secure_data_source.dart';
import 'vault_kdbx_service.dart';

class AndroidAutofillCoordinator with WidgetsBindingObserver {
  AndroidAutofillCoordinator({
    required this.autofillService,
    required this.getActiveDatabaseUseCase,
    required this.getSelectedKeyFilePathUseCase,
    required this.secureDataSource,
    required this.vaultKdbxService,
    required this.matcher,
    required this.passwordGenerator,
  });

  final AutofillService autofillService;
  final GetActiveDatabaseUseCase getActiveDatabaseUseCase;
  final GetSelectedKeyFilePathUseCase getSelectedKeyFilePathUseCase;
  final SecureDataSource secureDataSource;
  final VaultKdbxService vaultKdbxService;
  final VaultAutofillMatcher matcher;
  final PasswordGeneratorService passwordGenerator;

  static const Duration _requestDedupWindow = Duration(seconds: 2);
  static const Duration _entriesCacheTtl = Duration(seconds: 20);
  static const Duration _saveCompleteTimeout = Duration(seconds: 3);

  bool _initialized = false;
  bool _processing = false;
  bool _pendingFillRequest = false;
  String? _lastHandledRequestKey;
  DateTime? _lastHandledRequestAt;
  _AutofillEntriesCache? _entriesCache;

  Future<void> initialize() async {
    if (_initialized || !_isSupportedPlatform) {
      return;
    }

    _initialized = true;
    WidgetsBinding.instance.addObserver(this);

    try {
      // Disable IME inline suggestions to avoid a crash in FlutterAutofillService
      // when the keyboard sends an InlineSuggestionsRequest with maxSuggestionCount >= 2
      // but an empty inlinePresentationSpecs list (NoSuchElementException on .first()).
      await autofillService.setPreferences(
        AutofillPreferences(
          enableDebug: false,
          enableSaving: true,
          enableIMERequests: false,
        ),
      );
      await handlePendingRequest();
    } catch (e, st) {
      logError('Unable to initialize Android autofill coordinator.', e, st);
    }
  }

  /// Called by [VaultBloc] after the vault is successfully loaded.
  /// If a fill request was deferred because the vault was locked, this
  /// method retries the request now that credentials are available.
  Future<void> onVaultReady() async {
    if (!_pendingFillRequest) return;
    _pendingFillRequest = false;
    _lastHandledRequestKey = null;
    _lastHandledRequestAt = null;
    await handlePendingRequest();
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

      final fillRequestedAutomatic =
          await autofillService.fillRequestedAutomatic;
      final fillRequestedInteractive =
          await autofillService.fillRequestedInteractive;
      final hasFillRequest = fillRequestedAutomatic || fillRequestedInteractive;
      final metadata = await autofillService.autofillMetadata;
      final hasSaveRequest = metadata?.saveInfo != null;

      if (!hasFillRequest && !hasSaveRequest) {
        return;
      }

      final requestKey = _buildRequestKey(
        hasFillRequest: hasFillRequest,
        hasSaveRequest: hasSaveRequest,
        metadata: metadata,
      );
      if (_isDuplicateRequest(requestKey)) {
        return;
      }
      _markRequestHandled(requestKey);

      if (hasFillRequest) {
        await _handleFillRequest(metadata);
      }

      if (hasSaveRequest) {
        await _handleSaveRequest(metadata);
        // The plugin's native onSaveComplete handler never calls result.success(),
        // so invokeMethod would hang forever. Use a timeout to unblock _processing.
        await autofillService
            .onSaveComplete()
            .timeout(_saveCompleteTimeout, onTimeout: () {});
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

  Future<void> _handleFillRequest(AutofillMetadata? metadata) async {
    final context = await _resolveAutofillContext();
    if (context == null) {
      // Vault is locked or no database is selected. Rather than returning empty
      // results (which would close the AutofillActivity immediately), keep the
      // activity open so the user can unlock the vault. Once VaultBloc finishes
      // initialisation it will call onVaultReady() to retry this request.
      _pendingFillRequest = true;
      return;
    }

    _pendingFillRequest = false;

    try {
      final entries = await _resolveEntries(context);

      final matched = matcher.findBestMatches(
        entries: entries,
        packageNames: metadata?.packageNames ?? const {},
        webDomains:
            metadata?.webDomains
                .map((webDomain) => webDomain.domain)
                .toSet() ??
            const {},
      );

      final datasets = matched
          .map(
            (entry) => PwDataset(
              label: _buildLabel(entry.title, entry.username),
              username: entry.username,
              password: entry.password,
            ),
          )
          .toList(growable: true);

      // If no existing credentials match, offer a strong generated password
      if (datasets.isEmpty) {
        final generated = passwordGenerator.generate(
          const PasswordGeneratorOptions.defaults(),
        );
        datasets.insert(
          0,
          PwDataset(
            label: 'Generate secure password',
            username: '',
            password: generated,
          ),
        );
      }

      await autofillService.resultWithDatasets(datasets);
    } catch (e, st) {
      logError('Unable to build Android autofill dataset.', e, st);
      await autofillService.resultWithDatasets(const []);
    }
  }

  Future<void> _handleSaveRequest(AutofillMetadata? metadata) async {
    final saveInfo = metadata?.saveInfo;
    if (saveInfo == null) {
      return;
    }

    final username = saveInfo.username?.trim() ?? '';
    final password = saveInfo.password?.trim() ?? '';
    if (username.isEmpty || password.isEmpty) {
      return;
    }

    final context = await _resolveAutofillContext();
    if (context == null) {
      return;
    }

    try {
      final entries = await _resolveEntries(context);
      final matchedEntry = _findEntryForSave(
        entries,
        username: username,
        metadata: metadata,
      );

      if (matchedEntry != null) {
        await vaultKdbxService.updateEntry(
          databasePath: context.databasePath,
          password: context.masterPassword,
          keyFilePath: context.keyFilePath,
          entryId: matchedEntry.id,
          title: matchedEntry.title,
          username: username,
          entryPassword: password,
          url: matchedEntry.url,
          notes: matchedEntry.notes,
          customFields: matchedEntry.customFields,
        );
      } else {
        final saveTitle = _buildSaveTitle(metadata);
        final saveUrl = _buildSaveUrl(metadata);
        final rootGroupId = await _resolveRootGroupId(context);
        await vaultKdbxService.createEntry(
          databasePath: context.databasePath,
          password: context.masterPassword,
          keyFilePath: context.keyFilePath,
          groupId: rootGroupId,
          title: saveTitle,
          username: username,
          entryPassword: password,
          url: saveUrl,
          notes: '',
          customFields: _buildSaveCustomFields(metadata),
        );
      }

      _entriesCache = null;
    } catch (e, st) {
      logError('Unable to persist Android autofill save request.', e, st);
    }
  }

  Future<_AutofillContext?> _resolveAutofillContext() async {
    final active = await getActiveDatabaseUseCase();
    final databasePath = active?.canonicalPath;
    if (databasePath == null || databasePath.trim().isEmpty) {
      return null;
    }

    final password = await secureDataSource.getMasterPassword() ?? '';
    final keyFilePath = await getSelectedKeyFilePathUseCase();
    if (password.isEmpty &&
        (keyFilePath == null || keyFilePath.trim().isEmpty)) {
      return null;
    }

    return _AutofillContext(
      databasePath: databasePath,
      masterPassword: password,
      keyFilePath: keyFilePath,
    );
  }

  Future<List<VaultEntry>> _resolveEntries(_AutofillContext context) async {
    final now = DateTime.now();
    final cached = _entriesCache;
    if (cached != null &&
        cached.matches(
          databasePath: context.databasePath,
          keyFilePath: context.normalizedKeyFilePath,
          hasPassword: context.masterPassword.isNotEmpty,
        ) &&
        now.difference(cached.loadedAt) <= _entriesCacheTtl) {
      return cached.entries;
    }

    final entries = await vaultKdbxService.loadAllEntries(
      databasePath: context.databasePath,
      password: context.masterPassword,
      keyFilePath: context.keyFilePath,
    );

    _entriesCache = _AutofillEntriesCache(
      databasePath: context.databasePath,
      keyFilePath: context.normalizedKeyFilePath,
      hasPassword: context.masterPassword.isNotEmpty,
      loadedAt: now,
      entries: entries,
    );
    return entries;
  }

  Future<String> _resolveRootGroupId(_AutofillContext context) async {
    final snapshot = await vaultKdbxService.loadVault(
      databasePath: context.databasePath,
      password: context.masterPassword,
      keyFilePath: context.keyFilePath,
    );
    return snapshot.rootGroupId;
  }

  String _buildRequestKey({
    required bool hasFillRequest,
    required bool hasSaveRequest,
    required AutofillMetadata? metadata,
  }) {
    final packages = (metadata?.packageNames.toList() ?? const <String>[])
      ..sort();
    final domains =
        (metadata?.webDomains.map((item) => item.domain).toList() ??
              const <String>[])
          ..sort();
    final saveInfo = metadata?.saveInfo;

    return [
      hasFillRequest ? 'fill:1' : 'fill:0',
      hasSaveRequest ? 'save:1' : 'save:0',
      'packages:${packages.join(',')}',
      'domains:${domains.join(',')}',
      'saveUser:${_normalize(saveInfo?.username ?? '')}',
      'savePassword:${(saveInfo?.password ?? '').trim().isNotEmpty ? '1' : '0'}',
    ].join('|');
  }

  bool _isDuplicateRequest(String requestKey) {
    final lastKey = _lastHandledRequestKey;
    final lastAt = _lastHandledRequestAt;
    if (lastKey == null || lastAt == null) {
      return false;
    }
    if (lastKey != requestKey) {
      return false;
    }
    return DateTime.now().difference(lastAt) <= _requestDedupWindow;
  }

  void _markRequestHandled(String requestKey) {
    _lastHandledRequestKey = requestKey;
    _lastHandledRequestAt = DateTime.now();
  }

  VaultEntry? _findEntryForSave(
    List<VaultEntry> entries, {
    required String username,
    required AutofillMetadata? metadata,
  }) {
    final normalizedUsername = _normalize(username);
    final domains = _resolveRequestedDomains(metadata);
    final packages = _resolveRequestedPackages(metadata);

    for (final entry in entries) {
      if (_normalize(entry.username) != normalizedUsername) {
        continue;
      }
      if (_entryMatchesTargets(entry, domains: domains, packages: packages)) {
        return entry;
      }
    }
    return null;
  }

  Set<String> _resolveRequestedDomains(AutofillMetadata? metadata) {
    return metadata?.webDomains
            .map((item) => _normalizeDomain(item.domain))
            .where((domain) => domain.isNotEmpty)
            .toSet() ??
        const <String>{};
  }

  Set<String> _resolveRequestedPackages(AutofillMetadata? metadata) {
    return metadata?.packageNames
            .map(_normalize)
            .where((item) => item.isNotEmpty)
            .toSet() ??
        const <String>{};
  }

  bool _entryMatchesTargets(
    VaultEntry entry, {
    required Set<String> domains,
    required Set<String> packages,
  }) {
    if (domains.isNotEmpty) {
      final entryDomain = _domainFromUrl(entry.url);
      if (entryDomain.isEmpty) {
        return false;
      }
      if (domains.any((domain) => _domainsRelated(entryDomain, domain))) {
        return true;
      }
      return false;
    }

    if (packages.isNotEmpty) {
      final entryPackages = _extractPackageIdentifiers(entry);
      if (entryPackages.isEmpty) {
        return false;
      }
      return packages.any((item) => entryPackages.contains(item));
    }

    return false;
  }

  String _buildSaveTitle(AutofillMetadata? metadata) {
    final domains = _resolveRequestedDomains(metadata).toList()..sort();
    if (domains.isNotEmpty) {
      return domains.first;
    }

    final packages = _resolveRequestedPackages(metadata).toList()..sort();
    if (packages.isNotEmpty) {
      return packages.first;
    }

    return 'Saved credential';
  }

  String _buildSaveUrl(AutofillMetadata? metadata) {
    final domains = _resolveRequestedDomains(metadata).toList()..sort();
    if (domains.isEmpty) {
      return '';
    }
    return 'https://${domains.first}';
  }

  List<VaultCustomField> _buildSaveCustomFields(AutofillMetadata? metadata) {
    final packages = _resolveRequestedPackages(metadata).toList()..sort();
    if (packages.isEmpty) {
      return const [];
    }
    return [VaultCustomField(key: 'KPH: androidPackage', value: packages.join(','))];
  }

  Set<String> _extractPackageIdentifiers(VaultEntry entry) {
    final values = <String>{};
    for (final field in entry.customFields) {
      final normalizedKey = _normalize(field.key);
      final looksLikePackageField =
          normalizedKey.contains('package') ||
          normalizedKey.contains('bundle') ||
          normalizedKey.contains('androidapp') ||
          normalizedKey.contains('iosapp');
      if (!looksLikePackageField) {
        continue;
      }

      final splitValues = field.value
          .split(RegExp(r'[,;\s]+'))
          .map(_normalize)
          .where((value) => value.isNotEmpty);
      values.addAll(splitValues);
    }
    return values;
  }

  String _domainFromUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null) {
      return '';
    }

    return _normalizeDomain(uri.host);
  }

  bool _domainsRelated(String left, String right) {
    if (left == right) {
      return true;
    }
    return left.endsWith('.$right') || right.endsWith('.$left');
  }

  String _normalizeDomain(String value) {
    var normalized = _normalize(value);
    if (normalized.startsWith('www.')) {
      normalized = normalized.substring(4);
    }
    if (normalized.startsWith('m.')) {
      normalized = normalized.substring(2);
    }
    return normalized;
  }

  String _normalize(String value) {
    return value.trim().toLowerCase();
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

class _AutofillContext {
  const _AutofillContext({
    required this.databasePath,
    required this.masterPassword,
    required this.keyFilePath,
  });

  final String databasePath;
  final String masterPassword;
  final String? keyFilePath;

  String? get normalizedKeyFilePath {
    final value = keyFilePath?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }
}

class _AutofillEntriesCache {
  const _AutofillEntriesCache({
    required this.databasePath,
    required this.keyFilePath,
    required this.hasPassword,
    required this.loadedAt,
    required this.entries,
  });

  final String databasePath;
  final String? keyFilePath;
  final bool hasPassword;
  final DateTime loadedAt;
  final List<VaultEntry> entries;

  bool matches({
    required String databasePath,
    required String? keyFilePath,
    required bool hasPassword,
  }) {
    return this.databasePath == databasePath &&
        this.keyFilePath == keyFilePath &&
        this.hasPassword == hasPassword;
  }
}
