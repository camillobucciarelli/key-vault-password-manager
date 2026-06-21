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

class _BrowserSetupScreenState extends State<BrowserSetupScreen> {
  final _service = BrowserSetupService();

  // Step status
  _StepStatus _nativeHostStatus = _StepStatus.pending;
  _StepStatus _extensionStatus = _StepStatus.pending;
  _StepStatus _connectionStatus = _StepStatus.pending;

  String? _errorMessage;
  bool _isCheckingConnection = false;

  bool get _hasMacInstaller =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

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

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _checkInitialState() async {
    final bridge = await _service.checkBridgeConnection();
    if (!mounted) return;

    if (bridge == BridgeCheckResult.connected) {
      setState(() {
        _nativeHostStatus = _StepStatus.done;
        _extensionStatus = _StepStatus.done;
        _connectionStatus = _StepStatus.done;
      });
    }
  }

  Future<void> _openChromeExtensions() async {
    await _openExtensionFolder();

    // Show a dialog with the manual instruction
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Carica l\'estensione in Chrome'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '1. Apri Chrome e vai su:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            _CopyableCodeRow(text: 'chrome://extensions'),
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
              '4. Seleziona questa cartella del repo:',
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
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Registra Native Messaging Host ($_platformName)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chrome deve trovare il manifest del native host e il manifest deve consentire l\'ID della tua estensione.',
              ),
              const SizedBox(height: 14),
              if (Platform.isMacOS) ...[
                const Text(
                  '1. Copia l\'ID da chrome://extensions dopo aver caricato l\'estensione.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text('2. Esegui dal root del repo:'),
                const SizedBox(height: 6),
                _CopyableCodeRow(
                  text:
                      './desktop/native_host/install_host_macos.sh chrome <EXTENSION_ID>',
                ),
                const SizedBox(height: 8),
                const Text('Per Edge usa:'),
                const SizedBox(height: 6),
                _CopyableCodeRow(
                  text:
                      './desktop/native_host/install_host_macos.sh edge <EXTENSION_ID>',
                ),
              ] else if (Platform.isWindows) ...[
                const Text(
                  'Esegui PowerShell dal root del repo:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                const _CopyableCodeRow(
                  text:
                      '.\\desktop\\native_host\\install_host_windows.ps1 -Browser Chrome -ExtensionId <EXTENSION_ID>',
                ),
                const SizedBox(height: 8),
                const Text('Per Edge usa:'),
                const SizedBox(height: 6),
                const _CopyableCodeRow(
                  text:
                      '.\\desktop\\native_host\\install_host_windows.ps1 -Browser Edge -ExtensionId <EXTENSION_ID>',
                ),
              ] else if (Platform.isLinux) ...[
                const Text(
                  'Esegui dal root del repo:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                const _CopyableCodeRow(
                  text:
                      './desktop/native_host/install_host_linux.sh <EXTENSION_ID>',
                ),
                const SizedBox(height: 8),
                const Text('Per Chromium o Edge usa:'),
                const SizedBox(height: 6),
                const _CopyableCodeRow(
                  text:
                      './desktop/native_host/install_host_linux.sh --browser chromium <EXTENSION_ID>',
                ),
                const SizedBox(height: 6),
                const _CopyableCodeRow(
                  text:
                      './desktop/native_host/install_host_linux.sh --browser edge <EXTENSION_ID>',
                ),
              ] else ...[
                Text(
                  '$_platformName non è supportato da questa guida.',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 14),
              const Text(
                'Nome host usato dall\'estensione:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              _CopyableCodeRow(text: _service.nativeHostName),
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
      ),
    );
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
          _connectionStatus = _StepStatus.done;
        case BridgeCheckResult.noConfig:
          _connectionStatus = _StepStatus.error;
          _errorMessage =
              'App non avviata o bridge non ancora partito. '
              'Assicurati che KeyVault sia aperta e sbloccata. Config bridge: ${_service.bridgeConfigPath}';
        case BridgeCheckResult.notRunning:
          _connectionStatus = _StepStatus.error;
          _errorMessage =
              'Bridge non raggiungibile. Riavvia KeyVault, sblocca il vault e riprova.';
        case BridgeCheckResult.v2AppBridgeUnavailable:
          _connectionStatus = _StepStatus.error;
          _errorMessage =
              'Native Messaging v2 è in safe mode e non è ancora collegato al vault/app bridge. '
              'Il popup può verificare l\'host, ma queryCredentials/revealForFill rispondono senza segreti.';
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
    final allDone = _connectionStatus == _StepStatus.done;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        title: const Text('Estensione Chrome desktop'),
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
                                      'Estensione Chrome desktop',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Installa il bridge Native Messaging v2 in safe mode',
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
                            title: 'Carica l\'estensione in Chrome',
                            description:
                                'Apri chrome://extensions, abilita Modalità sviluppatore '
                                'e seleziona desktop/browser_extension dal repo.',
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
                            description: _hasMacInstaller
                                ? 'Copia l\'ID estensione e registra l\'host v2 con lo script del repo per $_platformName.'
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
                                'In questa milestone il popup verifica l\'host v2; il bridge vault/app reale non è ancora implementato.',
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
                          _TroubleshootingTips(platformName: _platformName),

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
                                      'apri il popup dell\'estensione sul sito, quindi usa '
                                      'Find credentials e Fill this account per compilare.',
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

class _TroubleshootingTips extends StatelessWidget {
  const _TroubleshootingTips({required this.platformName});

  final String platformName;

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
                'Safe mode v2: queryCredentials e revealForFill devono tornare errori sicuri finché il vault bridge reale non è implementato.',
          ),
          const _Tip(
            text:
                'Estensione non collegata: ricarica l\'estensione da chrome://extensions dopo aver aggiornato il manifest host.',
          ),
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
