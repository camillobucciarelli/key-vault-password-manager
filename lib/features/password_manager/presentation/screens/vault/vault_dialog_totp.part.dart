part of '../vault_screen.dart';

Future<void> _showTotpDialog(BuildContext context, VaultEntry entry) async {
  if (entry.otpUri != null) {
    await _showTotpUriDialog(context, entry.otpUri!);
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('OTP'),
        insetPadding: _dialogInsetPadding(dialogContext),
        contentPadding: _dialogContentPadding(dialogContext),
        actionsOverflowDirection: VerticalDirection.down,
        actionsOverflowButtonSpacing: 8,
        content: const Text('No valid OTP URI configured for this record.'),
        actions: _adaptiveDialogActions(dialogContext, [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ]),
      );
    },
  );
}

Future<void> _showTotpUriDialog(BuildContext context, String otpUri) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('OTP'),
        insetPadding: _dialogInsetPadding(dialogContext),
        contentPadding: _dialogContentPadding(dialogContext),
        actionsOverflowDirection: VerticalDirection.down,
        actionsOverflowButtonSpacing: 8,
        content: _TotpDialogContent(otpUri: otpUri),
        actions: _adaptiveDialogActions(dialogContext, [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ]),
      );
    },
  );
}

class _OtpQrScannerDialog extends StatefulWidget {
  const _OtpQrScannerDialog();

  @override
  State<_OtpQrScannerDialog> createState() => _OtpQrScannerDialogState();
}

class _OtpQrScannerDialogState extends State<_OtpQrScannerDialog> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _isHandlingCapture = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Scan OTP QR'),
      insetPadding: _dialogInsetPadding(context),
      contentPadding: _dialogContentPadding(context),
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: 8,
      content: SizedBox(
        width: _dialogContentWidth(context, 320),
        child: AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MobileScanner(
              controller: _controller,
              onDetect: (capture) async {
                if (_isHandlingCapture) {
                  return;
                }

                for (final barcode in capture.barcodes) {
                  final value = barcode.rawValue?.trim();
                  if (value == null || value.isEmpty) {
                    continue;
                  }

                  _isHandlingCapture = true;
                  if (value.startsWith('otpauth://')) {
                    if (context.mounted) {
                      Navigator.of(context).pop(value);
                    }
                    return;
                  }

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('QR does not contain a valid OTP URI.'),
                      ),
                    );
                  }
                  _isHandlingCapture = false;
                  return;
                }
              },
            ),
          ),
        ),
      ),
      actions: _adaptiveDialogActions(context, [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ]),
    );
  }
}

class _TotpDialogContent extends StatefulWidget {
  const _TotpDialogContent({required this.otpUri});

  final String otpUri;

  @override
  State<_TotpDialogContent> createState() => _TotpDialogContentState();
}

class _TotpDialogContentState extends State<_TotpDialogContent> {
  late Timer _timer;
  DateTime _nowUtc = DateTime.now().toUtc();

  int get _periodSeconds {
    final parsed = Uri.tryParse(widget.otpUri);
    final period = int.tryParse(parsed?.queryParameters['period'] ?? '');
    if (period == null || period <= 0) {
      return 30;
    }
    return period;
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _nowUtc = DateTime.now().toUtc();
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totpData = TotpUtils.fromOtpAuthUri(widget.otpUri, _nowUtc);
    if (totpData == null) {
      return const Text('Invalid OTP URI.');
    }

    final colorScheme = Theme.of(context).colorScheme;
    final periodSeconds = _periodSeconds;
    final remainingRatio = (totpData.remainingSeconds / periodSeconds)
        .clamp(0.0, 1.0)
        .toDouble();
    final previousRatio = totpData.remainingSeconds == periodSeconds
        ? 1.0
        : ((totpData.remainingSeconds + 1) / periodSeconds)
              .clamp(0.0, 1.0)
              .toDouble();
    final isExpiringSoon =
        totpData.remainingSeconds <= math.max(5, periodSeconds ~/ 5);
    final accentColor = isExpiringSoon
        ? AppColors.warning
        : colorScheme.secondary;
    final onAccentColor = isExpiringSoon
        ? (ThemeData.estimateBrightnessForColor(AppColors.warning) ==
                  Brightness.dark
              ? Colors.white
              : Colors.black87)
        : colorScheme.onSecondaryContainer;

    return SizedBox(
      width: _dialogContentWidth(context, 280),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accentColor.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  totpData.code,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontFeatures: const [],
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isExpiringSoon
                      ? 'Code in scadenza: ${totpData.remainingSeconds}s'
                      : 'Scade tra ${totpData.remainingSeconds}s',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: onAccentColor.withValues(alpha: 0.92),
                    fontWeight: isExpiringSoon
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: SizedBox(
                    width: 54,
                    height: 54,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        TweenAnimationBuilder<double>(
                          key: ValueKey<int>(totpData.remainingSeconds),
                          tween: Tween<double>(
                            begin: previousRatio,
                            end: remainingRatio,
                          ),
                          duration: const Duration(milliseconds: 940),
                          curve: Curves.linear,
                          builder: (context, animatedRatio, _) {
                            return CircularProgressIndicator(
                              value: animatedRatio,
                              strokeWidth: 4,
                              strokeCap: StrokeCap.round,
                              backgroundColor: accentColor.withValues(
                                alpha: 0.15,
                              ),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                accentColor,
                              ),
                            );
                          },
                        ),
                        AnimatedSwitcher(
                          duration: _VaultUiTokens.chipTransitionDuration,
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(opacity: animation, child: child),
                          child: Text(
                            '${totpData.remainingSeconds}s',
                            key: ValueKey<int>(totpData.remainingSeconds),
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: onAccentColor,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              animationDuration: _VaultUiTokens.buttonTransitionDuration,
            ),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: totpData.code));
              if (!context.mounted) {
                return;
              }
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('OTP copied.')));
            },
            icon: const Icon(AppIcons.copy),
            label: const Text('Copy code'),
          ),
        ],
      ),
    );
  }
}
