import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../core/theme/app_backgrounds.dart';
import '../../../../../core/theme/app_icons.dart';
import '../../data/services/browser_setup_service.dart';
import '../widgets/styled_info_container.dart';

/// A step-by-step wizard that guides the user through connecting the
/// KeyVault browser extension to the desktop app.
///
/// Should only be shown on desktop platforms.
class BrowserSetupScreen extends StatefulWidget {
  const BrowserSetupScreen({super.key, this.service});

  final BrowserSetupService? service;

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
  late final BrowserSetupService _service;

  // Step status
  _StepStatus _nativeHostStatus = _StepStatus.pending;
  _StepStatus _extensionStatus = _StepStatus.pending;
  _StepStatus _connectionStatus = _StepStatus.pending;

  String? _errorMessage;
  String? _nativeHostSetupMessage;
  bool _isCheckingConnection = false;
  bool _appBridgeConnected = false;

  bool get _usesMacOSCompanionInstaller =>
      defaultTargetPlatform == TargetPlatform.macOS;

  bool get _hasNativeHostInstaller =>
      _usesMacOSCompanionInstaller || _service.canRunNativeHostInstaller;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? BrowserSetupService();
    _checkInitialState();
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

  Future<void> _openChromeStore() async {
    setState(() {
      _extensionStatus = _StepStatus.loading;
      _errorMessage = null;
    });
    try {
      final opened = await launchUrl(
        Uri.parse(BrowserSetupService.chromeStoreListingUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      setState(() {
        _extensionStatus = opened ? _StepStatus.pending : _StepStatus.error;
        if (!opened) {
          _errorMessage = 'Impossibile aprire Chrome Web Store. Riprova.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _extensionStatus = _StepStatus.error;
        _errorMessage = 'Impossibile aprire Chrome Web Store. Riprova.';
      });
    }
  }

  Future<void> _installNativeHost() async {
    setState(() {
      _nativeHostStatus = _StepStatus.loading;
      _nativeHostSetupMessage = null;
      _errorMessage = null;
    });

    if (_usesMacOSCompanionInstaller) {
      var opened = false;
      try {
        opened = await launchUrl(
          Uri.parse(BrowserSetupService.macOSChromeSupportPackageUrl),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        opened = false;
      }
      if (!mounted) return;
      final message = opened
          ? 'Apri il pacchetto scaricato, completa l’installazione e riavvia Chrome.'
          : 'Impossibile scaricare Chrome Support per macOS.';
      setState(() {
        _nativeHostSetupMessage = message;
        _nativeHostStatus = opened ? _StepStatus.pending : _StepStatus.error;
        _errorMessage = opened ? null : message;
      });
      return;
    }

    final result = await _service.installNativeHost();
    if (!mounted) return;

    final success = result == NativeHostInstallResult.success;
    final message = _nativeHostInstallMessage(result);
    setState(() {
      _nativeHostSetupMessage = message;
      _nativeHostStatus = success ? _StepStatus.done : _StepStatus.error;
      _errorMessage = success ? null : message;
    });
  }

  String _nativeHostInstallMessage(NativeHostInstallResult result) {
    switch (result) {
      case NativeHostInstallResult.success:
        return 'Chrome configurato. Riavvia Chrome e verifica la connessione.';
      case NativeHostInstallResult.invalidExtensionId:
        return 'Configurazione Chrome non valida. Aggiorna KeyVault e riprova.';
      case NativeHostInstallResult.scriptNotFound:
        return 'Installer Chrome non disponibile in questa versione di KeyVault.';
      case NativeHostInstallResult.unsupportedPlatform:
        return 'Configurazione automatica di Chrome non supportata su questa piattaforma.';
      case NativeHostInstallResult.failed:
        return 'Configurazione Chrome non riuscita. Riprova o reinstalla KeyVault.';
    }
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
          _errorMessage = 'Sblocca il vault in KeyVault e riprova.';
        case BridgeCheckResult.notRunning:
          _appBridgeConnected = false;
          _connectionStatus = _StepStatus.error;
          _errorMessage =
              'Bridge non raggiungibile. Riavvia KeyVault, sblocca il vault e riprova.';
        case BridgeCheckResult.v2AppBridgeUnavailable:
          _appBridgeConnected = false;
          _connectionStatus = _StepStatus.error;
          _errorMessage =
              'Collegamento non disponibile. Blocca e sblocca il vault, poi riprova.';
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
                                      'Estensione Chrome',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Installa l\'estensione e collegala a KeyVault',
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

                          // Step 1 — Install Extension
                          _SetupStep(
                            number: 1,
                            title: 'Installa l\'estensione',
                            description:
                                'Apri Chrome Web Store e installa l\'estensione KeyVault.',
                            status: _extensionStatus,
                            actionLabel: _extensionStatus == _StepStatus.loading
                                ? 'Apertura in corso…'
                                : 'Apri Chrome Web Store',
                            onAction: _extensionStatus != _StepStatus.loading
                                ? _openChromeStore
                                : null,
                          ),

                          const SizedBox(height: 12),

                          // Step 2 — Native Host
                          _SetupStep(
                            number: 2,
                            title: 'Collega Chrome a KeyVault',
                            description: _usesMacOSCompanionInstaller
                                ? 'Scarica e installa il componente Chrome Support firmato per macOS.'
                                : _hasNativeHostInstaller
                                ? 'Configura automaticamente il collegamento sicuro con Chrome.'
                                : 'Installer Chrome non disponibile in questa versione di KeyVault.',
                            status: _nativeHostStatus,
                            actionLabel:
                                _nativeHostStatus == _StepStatus.loading
                                ? 'Configurazione in corso…'
                                : _usesMacOSCompanionInstaller
                                ? 'Scarica Chrome Support'
                                : 'Configura Chrome',
                            onAction: _nativeHostStatus != _StepStatus.loading
                                ? _installNativeHost
                                : null,
                          ),

                          if (_nativeHostSetupMessage != null &&
                              _nativeHostStatus != _StepStatus.error) ...[
                            const SizedBox(height: 12),
                            _InlineStatusMessage(
                              message: _nativeHostSetupMessage!,
                              isError: false,
                            ),
                          ],

                          const SizedBox(height: 12),

                          // Step 3 — Verify connection
                          _SetupStep(
                            number: 3,
                            title: 'Verifica la connessione',
                            description:
                                'Sblocca il vault e tieni KeyVault aperto, poi verifica che il bridge app sia pronto.',
                            status: _connectionStatus,
                            actionLabel: _isCheckingConnection
                                ? 'Verifica in corso…'
                                : 'Verifica',
                            onAction: !_isCheckingConnection
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

                          if (_appBridgeConnected) ...[
                            const SizedBox(height: 16),
                            Text(
                              'Ultimo controllo: riavvia Chrome e apri il popup KeyVault. La voce Host deve risultare Available.',
                              style: Theme.of(context).textTheme.bodySmall,
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
              'KeyVault è pronto per collegarsi all\'estensione Chrome.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
