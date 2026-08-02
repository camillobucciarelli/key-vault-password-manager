import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../core/theme/app_backgrounds.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../data/services/browser_setup_service.dart';
import '../widgets/styled_info_container.dart';

/// A step-by-step wizard that guides the user through connecting the
/// KeyVault browser extension to the desktop app.
///
/// Should only be shown on desktop platforms.
class BrowserSetupScreen extends StatefulWidget {
  const BrowserSetupScreen({super.key});

  static bool get shouldShow {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  @override
  State<BrowserSetupScreen> createState() => _BrowserSetupScreenState();
}

@visibleForTesting
class BrowserSetupInitialStatus {
  const BrowserSetupInitialStatus({
    required this.appBridgeConnected,
    required this.extensionStepCompleted,
    required this.nativeHostStepCompleted,
    required this.connectionStepCompleted,
  });

  final bool appBridgeConnected;
  final bool extensionStepCompleted;
  final bool nativeHostStepCompleted;
  final bool connectionStepCompleted;

  bool get allConfigured =>
      extensionStepCompleted &&
      nativeHostStepCompleted &&
      connectionStepCompleted;
}

@visibleForTesting
BrowserSetupInitialStatus browserSetupInitialStatusForBridge(
  BridgeCheckResult bridge,
) {
  return BrowserSetupInitialStatus(
    appBridgeConnected: bridge == BridgeCheckResult.connected,
    extensionStepCompleted: false,
    nativeHostStepCompleted: false,
    connectionStepCompleted: false,
  );
}

class _BrowserSetupScreenState extends State<BrowserSetupScreen> {
  final _service = BrowserSetupService();
  final _extensionIdController = TextEditingController();

  // Step status
  _StepStatus _nativeHostStatus = _StepStatus.pending;
  _StepStatus _extensionStatus = _StepStatus.pending;
  _StepStatus _connectionStatus = _StepStatus.pending;

  String? _errorMessage;
  String? _nativeHostSetupMessage;
  bool _nativeHostSetupMessageIsError = false;
  bool _isCheckingConnection = false;
  bool _appBridgeConnected = false;
  NativeHostBrowser? _registeringBrowser;

  bool get _hasNativeHostInstaller => _service.canRunNativeHostInstaller;

  String get _platformName {
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'desktop';
  }

  @override
  void initState() {
    super.initState();
    _checkInitialState();
  }

  @override
  void dispose() {
    _extensionIdController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _checkInitialState() async {
    final bridge = await _service.checkBridgeConnection();
    if (!mounted) return;

    final initialStatus = browserSetupInitialStatusForBridge(bridge);
    setState(() {
      _appBridgeConnected = initialStatus.appBridgeConnected;
      if (initialStatus.extensionStepCompleted) {
        _extensionStatus = _StepStatus.done;
      }
      if (initialStatus.nativeHostStepCompleted) {
        _nativeHostStatus = _StepStatus.done;
      }
      if (initialStatus.connectionStepCompleted) {
        _connectionStatus = _StepStatus.done;
      }
    });
  }

  Future<void> _openChromeExtensions() async {
    await _openExtensionFolder();

    // Show a dialog with the manual instruction
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Carica l\'estensione beta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '1. Apri Chrome o Edge e vai su:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            _CopyableCodeRow(text: 'chrome://extensions'),
            const SizedBox(height: 6),
            _CopyableCodeRow(text: 'edge://extensions'),
            const SizedBox(height: 14),
            const Text(
              '2. Abilita "Modalità sviluppatore" (in alto a destra)',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            const Text(
              '3. Clicca "Carica estensione non pacchettizzata"',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            const Text(
              '4. Seleziona questa cartella beta del repo:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            _CopyableCodeRow(
              text:
                  _service.extensionFolderPath ?? 'desktop/browser_extension/',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Ho fatto'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() => _extensionStatus = _StepStatus.done);
            },
            child: const Text('Estensione caricata ✓'),
          ),
        ],
      ),
    );
  }

  Future<void> _openExtensionFolder() async {
    final path = _service.extensionFolderPath;
    if (path == null) return;
    if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', [path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [path]);
    }
  }

  Future<void> _showNativeHostInstructions() async {
    if (!mounted) return;
    setState(() {
      _nativeHostSetupMessage = null;
      _registeringBrowser = null;
    });
    var dialogOpen = true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, dialogSetState) {
          void safeDialogSetState(VoidCallback fn) {
            if (dialogOpen) dialogSetState(fn);
          }

          final extensionId = _extensionIdController.text.trim();
          final isValidExtensionId = BrowserSetupService.isValidExtensionId(
            extensionId,
          );
          final commandExtensionId = isValidExtensionId
              ? extensionId
              : '<EXTENSION_ID>';
          final supportedBrowsers = _service.supportedBrowsers;

          return AlertDialog(
            title: Text('Registra Native Messaging Host ($_platformName)'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Il browser deve trovare il manifest del native host e il manifest deve consentire l\'ID della tua estensione beta.',
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '1. Incolla l\'ID estensione',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Lo trovi in chrome://extensions o edge://extensions dopo aver caricato la cartella beta.',
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _extensionIdController,
                    onChanged: (_) => safeDialogSetState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Extension ID',
                      hintText: 'abcdefghijklmnopabcdefghijklmnop',
                      errorText: extensionId.isEmpty || isValidExtensionId
                          ? null
                          : 'ID non valido: servono 32 lettere da a a p.',
                      suffixIcon: TextButton(
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          final text = data?.text?.trim();
                          if (text == null || text.isEmpty) return;
                          _extensionIdController.text = text;
                          _extensionIdController.selection =
                              TextSelection.collapsed(offset: text.length);
                          safeDialogSetState(() {});
                        },
                        child: const Text('Incolla'),
                      ),
                    ),
                  ),
                  if (isValidExtensionId) ...[
                    const SizedBox(height: 8),
                    _CopyableCodeRow(text: extensionId),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    '2. Registra host per browser',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _service.canRunNativeHostInstaller
                        ? 'Puoi registrare direttamente da KeyVault oppure copiare il comando.'
                        : 'Script non trovato vicino all\'app. Avvia KeyVault dal root del repo o copia il comando dal root.',
                  ),
                  if (supportedBrowsers.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final browser in supportedBrowsers)
                          FilledButton.tonal(
                            onPressed:
                                _service.canRunNativeHostInstaller &&
                                    isValidExtensionId &&
                                    _registeringBrowser == null
                                ? () => _registerNativeHost(
                                    browser,
                                    safeDialogSetState,
                                  )
                                : null,
                            child: Text(
                              _registeringBrowser == browser
                                  ? 'Registro ${_browserLabel(browser)}…'
                                  : 'Registra ${_browserLabel(browser)}',
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  for (final browser in supportedBrowsers) ...[
                    Text(
                      '${_browserLabel(browser)} command:',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    _CopyableCodeRow(
                      text: _service.nativeHostInstallCommandText(
                        browser: browser,
                        extensionId: commandExtensionId,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (_nativeHostSetupMessage != null) ...[
                    const SizedBox(height: 4),
                    _InlineStatusMessage(
                      message: _nativeHostSetupMessage!,
                      isError: _nativeHostSetupMessageIsError,
                    ),
                    const SizedBox(height: 10),
                  ],
                  const Text(
                    'Nome host usato dall\'estensione:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  _CopyableCodeRow(text: _service.nativeHostName),
                  const SizedBox(height: 12),
                  const Text(
                    'Dopo ogni registrazione riavvia il browser prima di testare il popup.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Chiudi'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  setState(() => _nativeHostStatus = _StepStatus.done);
                },
                child: const Text('Host registrato ✓'),
              ),
            ],
          );
        },
      ),
    );
    dialogOpen = false;
  }

  Future<void> _registerNativeHost(
    NativeHostBrowser browser,
    void Function(VoidCallback fn) dialogSetState,
  ) async {
    dialogSetState(() {
      _registeringBrowser = browser;
      _nativeHostSetupMessage = null;
    });

    final result = await _service.registerNativeHost(
      browser: browser,
      extensionId: _extensionIdController.text,
    );
    if (!mounted) return;

    final success = result == NativeHostInstallResult.success;
    final message = _nativeHostInstallMessage(result, browser);
    dialogSetState(() {
      _registeringBrowser = null;
      _nativeHostSetupMessage = message;
      _nativeHostSetupMessageIsError = !success;
    });
    setState(() {
      _registeringBrowser = null;
      _nativeHostSetupMessage = message;
      _nativeHostSetupMessageIsError = !success;
      _nativeHostStatus = success ? _StepStatus.done : _StepStatus.error;
      _errorMessage = success ? null : message;
    });
  }

  String _nativeHostInstallMessage(
    NativeHostInstallResult result,
    NativeHostBrowser browser,
  ) {
    final label = _browserLabel(browser);
    switch (result) {
      case NativeHostInstallResult.success:
        return 'Host registrato per $label. Riavvia il browser e verifica la connessione.';
      case NativeHostInstallResult.invalidExtensionId:
        return 'ID estensione non valido. Copia l\'ID da chrome://extensions o edge://extensions: 32 lettere da a a p.';
      case NativeHostInstallResult.scriptNotFound:
        return 'Script installer non trovato. Avvia KeyVault dal root del repo o copia/esegui il comando mostrato.';
      case NativeHostInstallResult.unsupportedPlatform:
        return 'Piattaforma non supportata dalla registrazione guidata.';
      case NativeHostInstallResult.failed:
        return 'Registrazione host fallita. Esegui il comando manuale e controlla i permessi del manifest.';
    }
  }

  String _browserLabel(NativeHostBrowser browser) {
    return switch (browser) {
      NativeHostBrowser.chrome => 'Chrome',
      NativeHostBrowser.edge => 'Edge',
      NativeHostBrowser.chromium => 'Chromium',
    };
  }

  Future<void> _checkConnection() async {
    setState(() {
      _isCheckingConnection = true;
      _connectionStatus = _StepStatus.loading;
      _errorMessage = null;
    });

    final result = await _service.checkBridgeConnection();
    if (!mounted) return;

    setState(() {
      _isCheckingConnection = false;
      switch (result) {
        case BridgeCheckResult.connected:
          _appBridgeConnected = true;
          _connectionStatus = _StepStatus.done;
        case BridgeCheckResult.noConfig:
          _appBridgeConnected = false;
          _connectionStatus = _StepStatus.error;
          _errorMessage =
              'Vault non ancora pubblicato per il browser. '
              'Sblocca KeyVault: il bridge parte automaticamente dopo unlock. Config bridge: ${_service.bridgeConfigPath}';
        case BridgeCheckResult.notRunning:
          _appBridgeConnected = false;
          _connectionStatus = _StepStatus.error;
          _errorMessage =
              'Bridge non raggiungibile. Riavvia KeyVault, sblocca il vault e riprova.';
        case BridgeCheckResult.v2AppBridgeUnavailable:
          _appBridgeConnected = false;
          _connectionStatus = _StepStatus.error;
          _errorMessage =
              'Cache metadata presente, ma reveal bridge non attivo. '
              'Blocca/sblocca il vault o riavvia KeyVault; il bridge locale si avvia dopo unlock. Cache: ${_service.bridgeConfigPath}';
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = viewportWidth < 420 ? 16.0 : 24.0;
    final cardPadding = viewportWidth < 420 ? 18.0 : 24.0;
    final topInset = MediaQuery.paddingOf(context).top;
    final allDone =
        _extensionStatus == _StepStatus.done &&
        _nativeHostStatus == _StepStatus.done &&
        _connectionStatus == _StepStatus.done;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        title: const Text('Estensione browser desktop'),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppBackgrounds.gradient(context)),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                topInset + 16,
                horizontalPadding,
                32,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  tween: Tween(begin: 0.97, end: 1),
                  builder: (context, v, child) => Transform.scale(
                    scale: v,
                    child: Opacity(opacity: v, child: child),
                  ),
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(cardPadding),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Row(
                            children: [
                              Icon(
                                AppIcons.key,
                                size: 36,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Estensione browser desktop beta',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Installa Native Messaging v2 e collega il reveal bridge locale',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          const Divider(height: 1),
                          const SizedBox(height: 20),

                          // Step 1 — Load Extension
                          _SetupStep(
                            number: 1,
                            title: 'Carica l\'estensione beta',
                            description:
                                'Apri chrome://extensions o edge://extensions, abilita Modalità sviluppatore e seleziona desktop/browser_extension.',
                            status: _extensionStatus,
                            actionLabel: 'Apri istruzioni →',
                            onAction: _extensionStatus != _StepStatus.loading
                                ? _openChromeExtensions
                                : null,
                          ),

                          const SizedBox(height: 12),

                          // Step 2 — Native Host
                          _SetupStep(
                            number: 2,
                            title: 'Registra il Native Messaging Host',
                            description: _hasNativeHostInstaller
                                ? 'Incolla l\'ID estensione e registra l\'host v2 per $_platformName. Puoi usare il pulsante app o copiare il comando.'
                                : 'Configura il manifest host per $_platformName usando i template presenti nel repo.',
                            status: _extensionStatus == _StepStatus.done
                                ? _nativeHostStatus
                                : _StepStatus.disabled,
                            actionLabel: 'Mostra istruzioni →',
                            onAction: _extensionStatus == _StepStatus.done
                                ? _showNativeHostInstructions
                                : null,
                          ),

                          const SizedBox(height: 12),

                          // Step 3 — Verify connection
                          _SetupStep(
                            number: 3,
                            title: 'Verifica la connessione',
                            description:
                                'Dopo lo sblocco del vault, KeyVault pubblica la cache metadata e avvia automaticamente il reveal bridge locale.',
                            status: _nativeHostStatus == _StepStatus.done
                                ? _connectionStatus
                                : _StepStatus.disabled,
                            actionLabel: _isCheckingConnection
                                ? 'Verifica in corso…'
                                : 'Verifica',
                            onAction:
                                _nativeHostStatus == _StepStatus.done &&
                                    !_isCheckingConnection
                                ? _checkConnection
                                : null,
                          ),

                          if (_appBridgeConnected) ...[
                            const SizedBox(height: 12),
                            const _AppBridgeStatusBanner(),
                          ],

                          // Error message
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .errorContainer
                                    .withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.error.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    AppIcons.warning,
                                    size: 16,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onErrorContainer,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 16),
                          _TroubleshootingTips(
                            platformName: _platformName,
                            buildCommand: _service.nativeHostBuildCommandText,
                          ),

                          // Success state
                          if (allDone) ...[
                            const SizedBox(height: 20),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.green.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    AppIcons.check,
                                    color: Colors.green,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Tutto configurato! Tieni l\'app aperta e sbloccata, '
                                      'apri il popup dell\'estensione beta sul sito, quindi cerca e compila le credenziali.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Colors.green.shade700,
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(AppIcons.check, size: 18),
                                label: const Text('Chiudi'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Supporting widgets
// ---------------------------------------------------------------------------

enum _StepStatus { pending, disabled, loading, done, error }

class _SetupStep extends StatelessWidget {
  const _SetupStep({
    required this.number,
    required this.title,
    required this.description,
    required this.status,
    required this.actionLabel,
    this.onAction,
  });

  final int number;
  final String title;
  final String description;
  final _StepStatus status;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final isDisabled = status == _StepStatus.disabled;
    final isDone = status == _StepStatus.done;
    final isLoading = status == _StepStatus.loading;
    final isError = status == _StepStatus.error;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color iconBgColor = colorScheme.surfaceContainerHighest;
    Color iconFgColor = colorScheme.onSurfaceVariant;
    Widget stepIcon = Text(
      '$number',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: iconFgColor,
      ),
    );

    if (isDone) {
      iconBgColor = Colors.green.withValues(alpha: 0.15);
      iconFgColor = Colors.green;
      stepIcon = Icon(AppIcons.check, size: 16, color: iconFgColor);
    } else if (isError) {
      iconBgColor = colorScheme.errorContainer.withValues(alpha: 0.4);
      iconFgColor = colorScheme.error;
      stepIcon = Icon(AppIcons.warning, size: 16, color: iconFgColor);
    } else if (isLoading) {
      iconBgColor = colorScheme.primaryContainer.withValues(alpha: 0.4);
      iconFgColor = colorScheme.primary;
      stepIcon = SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: iconFgColor),
      );
    } else if (!isDisabled) {
      iconBgColor = colorScheme.primaryContainer.withValues(alpha: 0.35);
      iconFgColor = colorScheme.primary;
      stepIcon = Text(
        '$number',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: iconFgColor,
        ),
      );
    }

    return Opacity(
      opacity: isDisabled ? 0.45 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDone
                ? Colors.green.withValues(alpha: isDark ? 0.3 : 0.42)
                : colorScheme.outlineVariant.withValues(
                    alpha: isDark ? 1 : 0.9,
                  ),
          ),
          color: isDone
              ? Colors.green.withValues(alpha: isDark ? 0.04 : 0.07)
              : colorScheme.surfaceContainerHighest.withValues(
                  alpha: isDark ? 0.25 : 0.62,
                ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Number / status indicator
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: iconBgColor,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: stepIcon,
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (!isDone && !isDisabled) ...[
                    const SizedBox(height: 10),
                    FilledButton.tonal(
                      onPressed: onAction,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 0,
                        ),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                      child: Text(actionLabel),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineStatusMessage extends StatelessWidget {
  const _InlineStatusMessage({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isError ? colorScheme.error : Colors.green;
    return StyledInfoContainer(
      padding: const EdgeInsets.all(10),
      borderRadius: 8,
      backgroundColor: color.withValues(alpha: 0.1),
      borderColor: color.withValues(alpha: 0.35),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? AppIcons.warning : AppIcons.check,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _AppBridgeStatusBanner extends StatelessWidget {
  const _AppBridgeStatusBanner();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return StyledInfoContainer(
      padding: const EdgeInsets.all(12),
      borderRadius: 10,
      backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.24),
      borderColor: colorScheme.primary.withValues(alpha: 0.25),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.info, size: 16, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'App bridge connesso: vault sbloccato e reveal bridge locale attivo. Ora carica l\'estensione e registra il native host.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _TroubleshootingTips extends StatelessWidget {
  const _TroubleshootingTips({required this.platformName, this.buildCommand});

  final String platformName;
  final String? buildCommand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return StyledInfoContainer(
      padding: const EdgeInsets.all(14),
      borderRadius: 12,
      backgroundColor: colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.55,
      ),
      borderColor: colorScheme.outlineVariant,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.info, size: 16, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Troubleshooting rapido',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Tip(
            text:
                'Chrome non vede l\'host: ricontrolla ID estensione, nome host e manifest native messaging per $platformName.',
          ),
          const _Tip(
            text:
                'Dopo unlock il bridge locale parte automaticamente; tieni KeyVault aperta e il vault sbloccato.',
          ),
          const _Tip(
            text:
                'Estensione non collegata: ricarica l\'estensione da chrome://extensions dopo aver aggiornato il manifest host.',
          ),
          const _Tip(
            text:
                'Native host has exited: compila il binario native host oppure assicurati che il launcher trovi Dart/Flutter/FVM nel PATH visibile al browser.',
          ),
          if (buildCommand != null) ...[
            const SizedBox(height: 8),
            _CopyableCodeRow(text: buildCommand!),
          ],
          const _Tip(
            text:
                'Permessi/path: il manifest deve puntare a un host eseguibile e leggibile dal browser.',
          ),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• '),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// A row that shows a monospace value with a copy-to-clipboard button.
class _CopyableCodeRow extends StatelessWidget {
  const _CopyableCodeRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return StyledInfoContainer(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      borderRadius: 8,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderColor: Theme.of(context).colorScheme.outlineVariant,
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copiato negli appunti'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                AppIcons.copy,
                size: 14,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
