part of 'database_unlock_screen.dart';

class _UnlockLoading extends StatelessWidget {
  const _UnlockLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

/// FR-5: full-screen dark biometric gate — circle 104 / glyph 50, centred
/// text, two stacked pills. Always dark regardless of app theme: wraps its
/// subtree in `AppTheme.darkTheme` so every descendant (including
/// `KvPillButton`) resolves `KeyVaultColors.dark` roles through the theme
/// extension instead of duplicating literal hex values.
class _BiometricGate extends StatelessWidget {
  const _BiometricGate({required this.onRetry, this.errorMessage});

  final VoidCallback onRetry;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.darkTheme,
      child: Builder(
        builder: (context) {
          final colors = Theme.of(context).extension<KeyVaultColors>()!;
          return ColoredBox(
            color: colors.ground,
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 104,
                        height: 104,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.actionFill,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          AppIcons.fingerprint,
                          size: 50,
                          color: colors.actionText,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Authenticate with biometrics',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.screenTitle.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      if (errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          errorMessage!,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.body.copyWith(
                            color: colors.attentionText,
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      KvPillButton(label: 'Retry', onPressed: onRetry),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// C-4 decrypting: entered before the KDBX await, indeterminate only, no
/// cancel affordance. Reduced motion freezes it to a static busy state.
class _DecryptingView extends StatelessWidget {
  const _DecryptingView({required this.basename});

  final String basename;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              liveRegion: true,
              label: 'Decrypting, please wait',
              child: SizedBox(
                width: 34,
                height: 34,
                child: reducedMotion
                    ? Icon(Icons.hourglass_top, color: colors.actionEmphasis)
                    : CircularProgressIndicator(
                        strokeWidth: 3,
                        color: colors.actionEmphasis,
                      ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Decrypting $basename',
              textAlign: TextAlign.center,
              style: AppTextStyles.sheetTitleLarge.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Deriving your encryption key with Argon2. This can take a moment.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// C-3: database-level failures (missing/invalid/corrupt) are a dead end
/// until the user goes back — never phrased as a credentials problem.
class _UnlockFailureView extends StatelessWidget {
  const _UnlockFailureView({required this.state, required this.onBack});

  final DatabaseUnlockState state;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 66,
              height: 66,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.attentionTint,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(AppIcons.warning, color: colors.attentionText),
            ),
            const SizedBox(height: 20),
            Text(
              state.errorMessage ?? 'This database could not be opened.',
              textAlign: TextAlign.center,
              style: AppTextStyles.sheetTitleLarge.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 24),
            KvPillButton(label: 'Back to database list', onPressed: onBack),
          ],
        ),
      ),
    );
  }
}

/// FR-5 ready state: feature square 66/radius24, title 32, password field
/// 56, primary pill, two inline links separated by a 1×14 divider.
class _UnlockReadyForm extends StatelessWidget {
  const _UnlockReadyForm({
    required this.state,
    required this.passwordCtrl,
    required this.passwordVisible,
    required this.onPasswordChanged,
    required this.onTogglePasswordVisible,
    required this.onPickKeyFile,
    required this.onClearKeyFile,
    required this.onSubmit,
    required this.onBack,
  });

  final DatabaseUnlockState state;
  final TextEditingController passwordCtrl;
  final bool passwordVisible;
  final VoidCallback onPasswordChanged;
  final VoidCallback onTogglePasswordVisible;
  final Future<void> Function() onPickKeyFile;
  final VoidCallback onClearKeyFile;

  /// Null disables the primary pill (C-5-adjacent: no credential entered).
  final VoidCallback? onSubmit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    final basename = p.basename(state.databasePath);
    final hasKeyFile =
        state.keyFilePath != null && state.keyFilePath!.trim().isNotEmpty;
    final isDesktopWidth =
        MediaQuery.sizeOf(context).width >= Breakpoints.mobile;

    final credentialError =
        state.failure != null &&
            (state.failure is InvalidCredentialsFailure ||
                state.failure is KeyFileMissingFailure)
        ? state.errorMessage
        : null;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isDesktopWidth ? 480 : double.infinity,
          ),
          child: TweenAnimationBuilder<double>(
            duration: AppMotion.duration(context, AppMotion.unlock),
            curve: AppMotion.inCurve,
            tween: Tween(begin: 0.98, end: 1),
            builder: (context, value, child) => Transform.scale(
              scale: value,
              child: Opacity(opacity: value, child: child),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 66,
                    height: 66,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.attentionTint,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(AppIcons.lock, color: colors.attentionText),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  basename,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.screenTitleLarge.copyWith(
                    fontSize: 32,
                    color: colors.textPrimary,
                  ),
                ),
                if (!isDesktopWidth) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Enter your master password or select a key file to '
                    'unlock this vault.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 56,
                  child: TextFormField(
                    controller: passwordCtrl,
                    obscureText: !passwordVisible,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => onPasswordChanged(),
                    onFieldSubmitted: (_) => onSubmit?.call(),
                    decoration: InputDecoration(
                      labelText: 'Master password',
                      helperText: hasKeyFile
                          ? 'Optional while a key file is selected.'
                          : 'Required if no key file is selected.',
                      errorText: credentialError,
                      prefixIcon: const Icon(AppIcons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          passwordVisible ? AppIcons.eyeOff : AppIcons.eye,
                        ),
                        onPressed: onTogglePasswordVisible,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _KeyFileSelector(
                  keyFilePath: state.keyFilePath,
                  onPickKeyFile: onPickKeyFile,
                  onClearKeyFile: onClearKeyFile,
                ),
                const SizedBox(height: 20),
                KvPillButton(
                  label: hasKeyFile ? 'Unlock with key file' : 'Unlock vault',
                  onPressed: onSubmit,
                ),
                  const SizedBox(height: 14),
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton(
                          onPressed: onBack,
                          child: const Text('Back to database list'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyFileSelector extends StatelessWidget {
  const _KeyFileSelector({
    required this.keyFilePath,
    required this.onPickKeyFile,
    required this.onClearKeyFile,
  });

  final String? keyFilePath;
  final Future<void> Function() onPickKeyFile;
  final VoidCallback onClearKeyFile;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;

    if (keyFilePath == null) {
      return OutlinedButton.icon(
        onPressed: onPickKeyFile,
        icon: const Icon(AppIcons.attachment),
        label: const Text('Select key file'),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceNested,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.fileKey, size: 20, color: colors.iconNeutral),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  !kIsWeb ? p.basename(keyFilePath!) : keyFilePath!,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          if (!kIsWeb) ...[
            const SizedBox(height: 4),
            Text(
              'Stored in app internal key storage.',
              style: AppTextStyles.secondary.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onPickKeyFile,
                icon: const Icon(AppIcons.edit),
                label: const Text('Change key file'),
              ),
              OutlinedButton.icon(
                onPressed: onClearKeyFile,
                icon: const Icon(AppIcons.close),
                label: const Text('Remove key file'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
