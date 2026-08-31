part of '../vault_screen.dart';

// Settings-owned surfaces move here as they are migrated from legacy dialogs.
//
// spec-006 T1/T2 (FR-1): `VaultDestination.settings` used to alias to the
// Backups destination (a spec-005 stopgap — see the comment that used to
// live on that switch arm). This file gives it its own screen: two
// `labelUpper` groups (Database / App) of `KvListRow`-style rows, matching
// mock screen 1 ("Impostazioni database") in
// `10-12 Sicurezza, autofill, estensione.dc.html`. Biometric / inactivity /
// key-file changes reuse `VaultSessionCoordinator.updateDatabaseSettings`
// (the same method the legacy dialog called) with `changePassword: false`,
// so no new re-key path is introduced here — only `ChangeMasterPasswordScreen`
// (T3) sets `changePassword: true`.

class _VaultSettingsDestination extends StatefulWidget {
  const _VaultSettingsDestination({
    required this.onCloseDatabase,
    this.onSecurityChanged,
  });

  /// Notifies the shell that the security profile changed, so it reloads the
  /// auto-lock timeout and the Settings attention badge.
  final VoidCallback? onSecurityChanged;

  /// Reuses `_VaultViewState._closeCurrentDatabaseAndSelectAnother` — same
  /// confirm dialog + `VaultSessionCoordinator.changeDatabase` + navigation
  /// the legacy sync-strip overflow menu's "Close database" action used.
  final Future<void> Function() onCloseDatabase;

  @override
  State<_VaultSettingsDestination> createState() =>
      _VaultSettingsDestinationState();
}

class _VaultSettingsDestinationState extends State<_VaultSettingsDestination> {
  bool _biometricEnabled = false;
  int? _inactivityTimeoutSeconds;
  String? _keyFilePath;
  bool _busy = false;
  String? _loadedForPath;
  String? _loadingForPath;

  Future<void> _ensureLoaded(String databasePath) async {
    if (_loadedForPath == databasePath ||
        _loadingForPath == databasePath ||
        databasePath.trim().isEmpty) {
      return;
    }
    _loadingForPath = databasePath;
    final coordinator = di.sl<VaultSessionCoordinator>();
    try {
      final biometricEnabled = await coordinator
          .getBiometricProtectionEnabledForPath(databasePath: databasePath);
      final inactivityTimeoutSeconds = await coordinator
          .getInactivityLockTimeoutForPath(databasePath: databasePath);
      final keyFilePath = await coordinator.getPersistedKeyFilePath(
        databasePath,
      );
      // Guard against a stale result: the vault's active path may have
      // moved on while these awaits were in flight (e.g. a concurrent
      // `_ensureLoaded` for a different path completed first).
      if (!mounted ||
          context.read<VaultBloc>().state.databasePath != databasePath) {
        return;
      }
      setState(() {
        _biometricEnabled = biometricEnabled;
        _inactivityTimeoutSeconds = inactivityTimeoutSeconds;
        _keyFilePath = keyFilePath;
        _loadedForPath = databasePath;
      });
    } catch (_) {
      // Silent: `_loadedForPath` stays unset for this path, so the next
      // `build()` retries. No UI is needed for a background settings load.
    } finally {
      // Only clear the guard for the in-flight path this call owns — a
      // concurrent `_ensureLoaded` for a different path may have already
      // overwritten `_loadingForPath` with its own value.
      if (_loadingForPath == databasePath) {
        _loadingForPath = null;
      }
    }
  }

  Future<bool> _persist(String databasePath) async {
    setState(() => _busy = true);
    try {
      await di.sl<VaultSessionCoordinator>().updateDatabaseSettings(
        DatabaseSettingsUpdateRequest(
          currentDatabasePath: databasePath,
          fileName: path.basename(databasePath),
          keyFilePath: _keyFilePath,
          biometricProtectionEnabled: _biometricEnabled,
          changePassword: false,
          inactivityLockTimeoutSeconds: _inactivityTimeoutSeconds,
        ),
      );
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to update database settings.')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setBiometricEnabled(String databasePath, bool value) async {
    if (_busy) return;
    final previous = _biometricEnabled;
    setState(() => _biometricEnabled = value);
    if (!await _persist(databasePath) && mounted) {
      setState(() => _biometricEnabled = previous);
    }
  }

  Future<void> _pickInactivityTimeout(String databasePath) async {
    if (_busy) return;
    final selected = await KvBottomSheet.show<Object?>(
      context: context,
      builder: (sheetContext) =>
          _InactivityTimeoutSheet(current: _inactivityTimeoutSeconds),
    );
    // Dismissing the sheet without picking (back gesture / tap outside)
    // resolves the `showModalBottomSheet` future with `null` — distinct
    // from an actual "Never" pick, which the sheet returns as the
    // `_kInactivityNever` sentinel (see `_InactivityTimeoutSheet`).
    if (selected == null || !mounted) {
      return;
    }
    final seconds = selected == _kInactivityNever ? null : selected as int;
    final previous = _inactivityTimeoutSeconds;
    setState(() => _inactivityTimeoutSeconds = seconds);
    if (!await _persist(databasePath) && mounted) {
      setState(() => _inactivityTimeoutSeconds = previous);
      return;
    }
    widget.onSecurityChanged?.call();
  }

  Future<void> _pickKeyFile(String databasePath) async {
    if (_busy) return;
    String? selectedPath;
    if (isManagedStoragePlatform) {
      final protectedPaths = await di
          .sl<VaultSessionCoordinator>()
          .getProtectedKeyFilePaths();
      if (!mounted) return;
      final result = await showInternalKeyFileManagerDialog(
        context,
        initiallySelectedPath: _keyFilePath,
        protectedPaths: {...protectedPaths, ?_keyFilePath},
      );
      if (result == null) return;
      selectedPath = result.selectedPath;
      if (selectedPath == null &&
          !(result.currentSelectionDeleted && _keyFilePath != null)) {
        return;
      }
    } else {
      final picked = await FilePicker.pickFiles(
        allowMultiple: false,
        withData: false,
      );
      final file = picked?.files.single;
      if (file?.path == null) return;
      selectedPath = file!.path;
    }

    if (!mounted) return;
    final previous = _keyFilePath;
    setState(() => _keyFilePath = selectedPath);
    if (!await _persist(databasePath) && mounted) {
      setState(() => _keyFilePath = previous);
    }
  }

  Future<void> _openAutofillSettings(BuildContext context) async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final entryCount = context.read<VaultBloc>().state.allEntries.length;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AutofillEnablementScreen(entryCount: entryCount),
        ),
      );
    } else if (BrowserSetupScreen.shouldShow) {
      await _openBrowserAutofillSettings(context);
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      await _openAndroidAutofillSettings(context);
    }
  }

  Future<void> _openBackups(BuildContext context) async {
    // Routes pushed on the app's shared Navigator are siblings of
    // `VaultScreen`'s own content, not descendants of it — the
    // `BlocProvider<VaultBloc>` created inside `VaultScreen.build()` is
    // otherwise invisible here (same rationale as `VaultShellRouterScope`
    // re-provisioning in `vault_shell_router.dart`'s `_defaultRouteHost`).
    final vaultBloc = context.read<VaultBloc>();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider<VaultBloc>.value(
          value: vaultBloc,
          child: Scaffold(
            appBar: AppBar(title: const Text('Backups & import')),
            body: const _VaultBackupsDestination(),
          ),
        ),
      ),
    );
  }

  Future<void> _openExternal(BuildContext context, String url) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to open $url')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return BlocBuilder<VaultBloc, VaultState>(
      buildWhen: (previous, current) =>
          previous.databasePath != current.databasePath,
      builder: (context, state) {
        final databasePath = state.databasePath;
        if (databasePath.trim().isEmpty) {
          return const SizedBox.shrink();
        }
        unawaited(_ensureLoaded(databasePath));

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settings',
                style: AppTextStyles.screenTitle.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              Text(
                path.basename(databasePath),
                style: AppTextStyles.body.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 18),
              _SettingsGroupLabel('Database'),
              const SizedBox(height: 8),
              Text(
                'Database file name',
                style: AppTextStyles.secondary.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Text(
                  path.basename(databasePath),
                  style: AppTextStyles.fieldValue.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _SettingsSwitchRow(
                glyph: AppGlyph.fingerprint,
                iconBackground: colors.positiveTint,
                iconColor: colors.positiveText,
                title: 'Biometric protection',
                subtitle: 'Unlock requires Face ID when available',
                value: _biometricEnabled,
                onChanged: _busy
                    ? null
                    : (value) => _setBiometricEnabled(databasePath, value),
              ),
              const SizedBox(height: 8),
              _SettingsRow(
                glyph: AppGlyph.clock,
                title: 'Lock on inactivity',
                subtitle: _inactivityTimeoutLabel(_inactivityTimeoutSeconds),
                onTap: _busy
                    ? null
                    : () => _pickInactivityTimeout(databasePath),
              ),
              // 2026-08-31: auto-lock only runs when configured, so an
              // unset vault says so where it can be fixed (the rail badge
              // points here).
              if (_inactivityTimeoutSeconds == null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: colors.attentionTint,
                    border: Border.all(color: colors.actionFill),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      KvIcon(
                        glyph: AppGlyph.lock,
                        size: 17,
                        color: colors.attentionText,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Auto-lock is off. Enable it so the vault locks '
                          'itself when you step away.',
                          style: AppTextStyles.secondary.copyWith(
                            color: colors.attentionText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _SettingsRow(
                glyph: AppGlyph.lock,
                title: 'Change master password',
                subtitle: 'Re-encrypts the whole file',
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChangeMasterPasswordScreen(
                        databasePath: databasePath,
                      ),
                    ),
                  );
                  _loadedForPath = null;
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(height: 8),
              _SettingsRow(
                glyph: AppGlyph.key,
                title: 'Key file',
                subtitle: _keyFilePath == null || _keyFilePath!.trim().isEmpty
                    ? 'None configured'
                    : path.basename(_keyFilePath!),
                onTap: _busy ? null : () => _pickKeyFile(databasePath),
              ),
              const SizedBox(height: 18),
              _SettingsGroupLabel('App'),
              const SizedBox(height: 8),
              _SettingsRow(
                glyph: AppGlyph.sun,
                title: 'Appearance',
                subtitle: null,
                onTap: null,
                trailing: const SizedBox.shrink(),
              ),
              const SizedBox(height: 8),
              const _ThemeSelector(),
              const SizedBox(height: 8),
              _SettingsRow(
                glyph: AppGlyph.desktop,
                title: 'Autofill & browsers',
                subtitle: 'Face ID keyboard, desktop helper',
                onTap: () => _openAutofillSettings(context),
              ),
              const SizedBox(height: 8),
              _SettingsRow(
                glyph: AppGlyph.export,
                title: 'Backups & import',
                subtitle: null,
                onTap: () => _openBackups(context),
              ),
              const SizedBox(height: 18),
              _SettingsGroupLabel('About'),
              const SizedBox(height: 8),
              _SettingsRow(
                glyph: AppGlyph.fileText,
                title: 'Open source licences',
                subtitle: 'Third-party notices bundled with this build',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: _kApplicationName,
                  applicationVersion: _kApplicationVersion,
                  applicationLegalese: _kApplicationLegalese,
                ),
              ),
              const SizedBox(height: 8),
              _SettingsRow(
                glyph: AppGlyph.shieldCheck,
                title: 'Privacy policy',
                subtitle: null,
                onTap: () => _openExternal(context, _kPrivacyPolicyUrl),
              ),
              const SizedBox(height: 8),
              _SettingsRow(
                glyph: AppGlyph.linkSimple,
                title: 'App licence',
                subtitle: 'AGPL-3.0',
                onTap: () => _openExternal(context, _kAppLicenceUrl),
              ),
              const SizedBox(height: 18),
              Center(child: _SettingsClosePill(onTap: widget.onCloseDatabase)),
            ],
          ),
        );
      },
    );
  }
}

const _kApplicationName = 'KeyVault';

/// Marketing version, mirrored by hand from `pubspec.yaml` `version:`.
/// `.github/workflows/release.yml` only bumps the build number after the `+`,
/// so this string changes only on a deliberate release bump. Kept literal so
/// no runtime dependency (e.g. `package_info_plus`) has to be added.
const _kApplicationVersion = '0.3.0';

const _kApplicationLegalese =
    'Copyright (C) 2026 Camillo Bucciarelli - AGPL-3.0';

const _kPrivacyPolicyUrl =
    'https://github.com/camillobucciarelli/key-vault-password-manager/blob/main/PRIVACY.md';

const _kAppLicenceUrl =
    'https://github.com/camillobucciarelli/key-vault-password-manager/blob/main/LICENSE';

String _inactivityTimeoutLabel(int? seconds) {
  if (seconds == null) return 'Never';
  if (seconds < 60) return 'After $seconds seconds';
  final minutes = seconds ~/ 60;
  return 'After $minutes minute${minutes == 1 ? '' : 's'}';
}

const _kInactivityNever = Object();

class _InactivityTimeoutSheet extends StatelessWidget {
  const _InactivityTimeoutSheet({required this.current});

  final int? current;

  static const _options = <int?>[null, 10, 20, 30, 60, 120, 300];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lock on inactivity',
            style: AppTextStyles.sheetTitle.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 14),
          for (final option in _options) ...[
            KvListRow(
              title: _inactivityTimeoutLabel(option),
              trailing: option == current
                  ? KvIcon(
                      glyph: AppGlyph.check,
                      size: 18,
                      color: colors.actionEmphasis,
                    )
                  : const SizedBox.shrink(),
              onTap: () =>
                  Navigator.of(context).pop(option ?? _kInactivityNever),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _SettingsGroupLabel extends StatelessWidget {
  const _SettingsGroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return Text(
      label,
      style: AppTextStyles.labelUpper.copyWith(color: colors.textSecondary),
    );
  }
}

/// FR-1 `.frow`: radius 22, padding 13/16, gap 12, 40-square leading glyph,
/// title 14.5/600, subtitle 12/400, chevron trailing when [onTap] is set.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.glyph,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final AppGlyph glyph;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    final resolvedTrailing =
        trailing ??
        (onTap == null
            ? null
            : KvIcon(
                glyph: AppGlyph.chevronRight,
                size: 17,
                color: colors.textTertiary,
              ));

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.surfaceNested,
              borderRadius: BorderRadius.circular(14),
            ),
            child: KvIcon(glyph: glyph, size: 19, color: colors.iconNeutral),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.bodyFamily,
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                  ).copyWith(color: colors.textPrimary),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: AppTextStyles.metaLarge.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (resolvedTrailing != null) ...[
            const SizedBox(width: 8),
            resolvedTrailing,
          ],
        ],
      ),
    );

    return onTap == null
        ? content
        : Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(22),
              child: content,
            ),
          );
  }
}

/// FR-1: the biometric-protection row, same geometry as [_SettingsRow] but
/// with a `KvSwitch` trailing instead of a chevron and an
/// `align-items: flex-start` leading icon tint (mock uses `accent-2` here).
class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.glyph,
    required this.iconBackground,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final AppGlyph glyph;
  final Color iconBackground;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(14),
            ),
            child: KvIcon(glyph: glyph, size: 19, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.bodyFamily,
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                  ).copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTextStyles.metaLarge.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          KvSwitch(value: value, onChanged: onChanged, semanticLabel: title),
        ],
      ),
    );
  }
}

/// FR-1/T2/AC4: three equal pills mapped 1:1 to `ThemeMode.values`
/// (`system`, `light`, `dark` — Flutter's enum has exactly three members,
/// so iterating it can never produce a fourth option).
class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector();

  static String _label(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
    ThemeMode.system => 'System',
  };

  @override
  Widget build(BuildContext context) {
    final current = context.watch<ThemeCubit>().state;

    return Row(
      children: [
        for (final mode in ThemeMode.values) ...[
          if (mode != ThemeMode.values.first) const SizedBox(width: 8),
          Expanded(
            child: _ThemePill(
              label: _label(mode),
              selected: mode == current,
              onTap: () => context.read<ThemeCubit>().setTheme(mode),
            ),
          ),
        ],
      ],
    );
  }
}

class _ThemePill extends StatelessWidget {
  const _ThemePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return Material(
      color: selected ? colors.actionFill : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: selected ? null : Border.all(color: colors.divider),
          ),
          child: Text(
            label,
            style:
                const TextStyle(
                  fontFamily: AppTextStyles.headingFamily,
                  fontSize: 13.5,
                ).copyWith(
                  color: selected ? colors.actionText : colors.textPrimary,
                ),
          ),
        ),
      ),
    );
  }
}

/// FR-1: "Close database" secondary pill, `linkText` colour, `pills` border.
class _SettingsClosePill extends StatelessWidget {
  const _SettingsClosePill({required this.onTap});

  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: () => onTap(),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colors.divider),
          ),
          child: Text(
            'Close database',
            style: const TextStyle(
              fontFamily: AppTextStyles.headingFamily,
              fontSize: 15,
            ).copyWith(color: colors.linkText),
          ),
        ),
      ),
    );
  }
}

Future<void> _showDatabaseSettings(
  BuildContext context,
  VaultState state,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final currentDatabasePath = state.databasePath;
  if (currentDatabasePath.trim().isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No active database selected.')),
    );
    return;
  }

  var databaseTitle = path.basenameWithoutExtension(currentDatabasePath);
  final sessionCoordinator = di.sl<VaultSessionCoordinator>();
  final persistedCurrentKeyPath = await sessionCoordinator
      .getPersistedKeyFilePath(currentDatabasePath);
  final protectedKeyFilePaths = await sessionCoordinator
      .getProtectedKeyFilePaths();
  if (!context.mounted) {
    return;
  }
  var pendingSelectedKeyPath = persistedCurrentKeyPath;
  var currentPassword = '';
  var newPassword = '';
  var confirmNewPassword = '';
  var changePassword = false;
  var biometricEnabled = await di
      .sl<VaultSessionCoordinator>()
      .getBiometricProtectionEnabledForPath(databasePath: currentDatabasePath);
  final initialBiometricEnabled = biometricEnabled;
  var inactivityTimeout = await di
      .sl<VaultSessionCoordinator>()
      .getInactivityLockTimeoutForPath(databasePath: currentDatabasePath);
  final initialInactivityTimeout = inactivityTimeout;
  final initialFileName = path.basename(currentDatabasePath);
  final normalizedCurrentKeyPath = _normalizeKeyPathForComparison(
    persistedCurrentKeyPath,
  );
  if (!context.mounted) {
    return;
  }
  final formKey = GlobalKey<FormState>();

  final shouldApply = await VaultShellRouterScope.of(context).open<DatabaseSettingsResult>(
    context: context,
    surface: DatabaseSettingsSurface<DatabaseSettingsResult>(
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            final normalizedSelectedKeyPath = _normalizeKeyPathForComparison(
              pendingSelectedKeyPath,
            );
            final keyFileChanged =
                normalizedSelectedKeyPath != normalizedCurrentKeyPath;
            final fileNameChanged =
                _normalizeDatabaseFileName(databaseTitle) != initialFileName;
            final biometricChanged =
                biometricEnabled != initialBiometricEnabled;
            final inactivityChanged =
                inactivityTimeout != initialInactivityTimeout;
            final hasSelectedKeyFile =
                pendingSelectedKeyPath?.trim().isNotEmpty ?? false;
            final pendingChanges = <String>[
              if (fileNameChanged) 'Database file name',
              if (biometricChanged) 'Biometric protection',
              if (inactivityChanged) 'Inactivity lock',
              if (keyFileChanged) 'Key file',
              if (changePassword) 'Master password',
            ];

            Future<void> selectKeyFile() async {
              if (isManagedStoragePlatform) {
                final currentSelectedPath = pendingSelectedKeyPath;
                final result = await showInternalKeyFileManagerDialog(
                  dialogContext,
                  initiallySelectedPath: currentSelectedPath,
                  protectedPaths: {
                    ...protectedKeyFilePaths,
                    ?persistedCurrentKeyPath,
                    ?pendingSelectedKeyPath,
                  },
                );
                if (result == null || !dialogContext.mounted) {
                  return;
                }
                setState(() {
                  if (result.selectedPath != null) {
                    pendingSelectedKeyPath = result.selectedPath;
                    return;
                  }
                  if (result.currentSelectionDeleted &&
                      currentSelectedPath != null &&
                      currentSelectedPath.trim().isNotEmpty) {
                    pendingSelectedKeyPath = null;
                  }
                });
                return;
              }

              final picked = await FilePicker.pickFiles(
                allowMultiple: false,
                withData: false,
              );
              if (!dialogContext.mounted) {
                return;
              }
              final selectedFile = picked?.files.single;
              if (selectedFile == null) {
                return;
              }

              final selectedPath = selectedFile.path;
              if (selectedPath == null || selectedPath.isEmpty) {
                return;
              }

              setState(() {
                pendingSelectedKeyPath = selectedPath;
              });
            }

            return AlertDialog(
              title: const Text('Database settings'),
              insetPadding: _dialogInsetPadding(dialogContext),
              contentPadding: _dialogContentPadding(dialogContext),
              actionsOverflowDirection: VerticalDirection.down,
              actionsOverflowButtonSpacing: 8,
              content: SizedBox(
                width: _dialogContentWidth(dialogContext, 520),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _DatabaseSettingsHeader(
                          databaseName: path.basenameWithoutExtension(
                            currentDatabasePath,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _DatabaseSettingsSectionCard(
                          icon: AppIcons.file,
                          title: 'Vault file',
                          subtitle: 'Change how this local database appears.',
                          children: [
                            TextFormField(
                              initialValue: databaseTitle,
                              decoration: const InputDecoration(
                                labelText: 'Database file name',
                                helperText:
                                    'The .kdbx extension is added automatically.',
                                prefixIcon: Icon(AppIcons.file),
                              ),
                              onChanged: (value) {
                                databaseTitle = value;
                                setState(() {});
                              },
                              validator: (value) {
                                final raw = value?.trim() ?? '';
                                if (raw.isEmpty) {
                                  return 'Database file name is required.';
                                }
                                if (raw.contains(RegExp(r'[\\/:*?"<>|]'))) {
                                  return 'Invalid characters in file name.';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _DatabaseSettingsSectionCard(
                          icon: AppIcons.lock,
                          title: 'Security & lock',
                          subtitle:
                              'Control quick unlock and automatic locking.',
                          children: [
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Biometric protection'),
                              subtitle: const Text(
                                'Allow face, fingerprint, or device biometrics to unlock this vault.',
                              ),
                              value: biometricEnabled,
                              onChanged: (value) {
                                setState(() {
                                  biometricEnabled = value;
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int?>(
                              initialValue: inactivityTimeout,
                              decoration: const InputDecoration(
                                labelText: 'Lock on inactivity',
                                helperText:
                                    'Automatically lock this vault after no activity.',
                                prefixIcon: Icon(AppIcons.lock),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: null,
                                  child: Text('Never'),
                                ),
                                DropdownMenuItem(
                                  value: 10,
                                  child: Text('10 seconds'),
                                ),
                                DropdownMenuItem(
                                  value: 20,
                                  child: Text('20 seconds'),
                                ),
                                DropdownMenuItem(
                                  value: 30,
                                  child: Text('30 seconds'),
                                ),
                                DropdownMenuItem(
                                  value: 60,
                                  child: Text('1 minute'),
                                ),
                                DropdownMenuItem(
                                  value: 120,
                                  child: Text('2 minutes'),
                                ),
                                DropdownMenuItem(
                                  value: 300,
                                  child: Text('5 minutes'),
                                ),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  inactivityTimeout = value;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _DatabaseSettingsSectionCard(
                          icon: AppIcons.fileKey,
                          title: 'Unlock credentials',
                          subtitle:
                              'Update the key file or master password used to open this vault.',
                          children: [
                            _DatabaseSettingsKeyFilePanel(
                              selectedKeyPath: pendingSelectedKeyPath,
                              onChange: selectKeyFile,
                              onRemove: !hasSelectedKeyFile
                                  ? null
                                  : () {
                                      setState(() {
                                        pendingSelectedKeyPath = null;
                                      });
                                    },
                            ),
                            const SizedBox(height: 10),
                            const _DatabaseSettingsInfoCallout(
                              icon: AppIcons.warning,
                              text:
                                  'Key file changes affect the next unlock. Google Drive sync stores only the .kdbx database; it does not sync key files, so keep a separate backup.',
                            ),
                            const SizedBox(height: 12),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Change master password'),
                              subtitle: const Text(
                                'Re-encrypts this vault. Use the new password the next time you unlock.',
                              ),
                              value: changePassword,
                              onChanged: (value) {
                                setState(() {
                                  changePassword = value;
                                });
                              },
                            ),
                            if (changePassword) ...[
                              const SizedBox(height: 8),
                              TextFormField(
                                initialValue: currentPassword,
                                obscureText: true,
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: const InputDecoration(
                                  labelText: 'Current master password',
                                  helperText:
                                      'Leave empty only if this vault currently uses a key file without a password.',
                                  prefixIcon: Icon(AppIcons.lock),
                                ),
                                onChanged: (value) {
                                  currentPassword = value;
                                },
                                validator: (value) {
                                  if (!changePassword) {
                                    return null;
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                initialValue: newPassword,
                                obscureText: true,
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: const InputDecoration(
                                  labelText: 'New master password',
                                  prefixIcon: Icon(AppIcons.key),
                                ),
                                onChanged: (value) {
                                  newPassword = value;
                                },
                                validator: (value) {
                                  if (!changePassword) {
                                    return null;
                                  }
                                  if ((value ?? '').isEmpty) {
                                    return 'New password is required.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                initialValue: confirmNewPassword,
                                obscureText: true,
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: const InputDecoration(
                                  labelText: 'Confirm new password',
                                  prefixIcon: Icon(AppIcons.check),
                                ),
                                onChanged: (value) {
                                  confirmNewPassword = value;
                                },
                                validator: (value) {
                                  if (!changePassword) {
                                    return null;
                                  }
                                  if ((value ?? '') != newPassword) {
                                    return 'Passwords do not match.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 8),
                              const _DatabaseSettingsInfoCallout(
                                icon: AppIcons.lock,
                                text:
                                    'Password changes affect the next unlock. Confirm the change before saving security credentials.',
                              ),
                            ],
                          ],
                        ),
                        if (pendingChanges.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _DatabaseSettingsChangesSummary(
                            changes: pendingChanges,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              actions: _adaptiveDialogActions(dialogContext, [
                TextButton(
                  onPressed: () =>
                      VaultOperationScope.of(dialogContext).cancel(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: pendingChanges.isEmpty
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) {
                            return;
                          }
                          if (changePassword || keyFileChanged) {
                            final securityChanges = <String>[
                              if (changePassword) 'Master password',
                              if (keyFileChanged) 'Key file',
                            ];
                            final confirmed = await _showConfirmation(
                              dialogContext,
                              title: 'Confirm security changes',
                              body:
                                  'You are about to update: ${securityChanges.join(' + ')}. '
                                  'Use the new credentials to unlock this vault after saving.',
                              confirmLabel: 'Confirm and apply',
                            );
                            if (confirmed != ConfirmDecision.confirm) {
                              return;
                            }
                          }
                          if (!dialogContext.mounted) {
                            return;
                          }
                          VaultOperationScope.of(dialogContext).complete(
                            DatabaseSettingsResult(
                              fileName: databaseTitle.trim(),
                              keyFilePath: pendingSelectedKeyPath,
                              biometricProtectionEnabled: biometricEnabled,
                              changePassword: changePassword,
                              inactivityLockTimeoutSeconds: inactivityTimeout,
                              currentPassword: currentPassword,
                              newPassword: newPassword,
                            ),
                          );
                        },
                  child: const Text('Save changes'),
                ),
              ]),
            );
          },
        );
      },
    ),
  );

  if (!context.mounted) {
    return;
  }

  if (shouldApply == null) {
    return;
  }

  final keyFileChanged =
      _normalizeKeyPathForComparison(persistedCurrentKeyPath) !=
      _normalizeKeyPathForComparison(shouldApply.keyFilePath);
  final requestedPasswordChange = shouldApply.changePassword;

  try {
    final result = await di
        .sl<VaultSessionCoordinator>()
        .updateDatabaseSettings(
          DatabaseSettingsUpdateRequest(
            currentDatabasePath: currentDatabasePath,
            fileName: shouldApply.fileName,
            keyFilePath: shouldApply.keyFilePath,
            biometricProtectionEnabled: shouldApply.biometricProtectionEnabled,
            changePassword: shouldApply.changePassword,
            inactivityLockTimeoutSeconds:
                shouldApply.inactivityLockTimeoutSeconds,
            currentPassword: shouldApply.currentPassword,
            newPassword: shouldApply.newPassword,
          ),
        );

    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.passwordChanged && keyFileChanged
              ? 'Database settings updated. Master password and key file changed successfully.'
              : result.passwordChanged
              ? 'Database settings updated. Master password changed successfully.'
              : keyFileChanged
              ? 'Database settings updated. Key file updated successfully.'
              : requestedPasswordChange
              ? 'Database settings updated.'
              : 'Database settings updated.',
        ),
      ),
    );
    await AppNavigation.pushFadeReplacement(
      context,
      VaultScreen(databasePath: result.databasePath),
    );
  } catch (_) {
    if (context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Unable to update database settings.')),
      );
    }
  }
}

String _normalizeDatabaseFileName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return trimmed.toLowerCase().endsWith('.kdbx') ? trimmed : '$trimmed.kdbx';
}

String? _normalizeKeyPathForComparison(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

class _DatabaseSettingsHeader extends StatelessWidget {
  const _DatabaseSettingsHeader({required this.databaseName});

  final String databaseName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              AppIcons.fileKey,
              size: 20,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  databaseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage vault name, lock behavior and unlock credentials.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.82,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DatabaseSettingsSectionCard extends StatelessWidget {
  const _DatabaseSettingsSectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 17, color: colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _DatabaseSettingsKeyFilePanel extends StatelessWidget {
  const _DatabaseSettingsKeyFilePanel({
    required this.selectedKeyPath,
    required this.onChange,
    required this.onRemove,
  });

  final String? selectedKeyPath;
  final VoidCallback onChange;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final keyPath = selectedKeyPath?.trim() ?? '';
    final hasKeyFile = keyPath.isNotEmpty;
    final title = hasKeyFile ? path.basename(keyPath) : 'No key file selected';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                hasKeyFile ? AppIcons.fileKey : AppIcons.file,
                size: 22,
                color: hasKeyFile
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasKeyFile
                          ? 'Stored in app key storage.'
                          : 'Add a key file for two-factor unlock with password + file.',
                      maxLines: hasKeyFile ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final stackButtons = constraints.maxWidth < 360;
              final changeButton = OutlinedButton.icon(
                onPressed: onChange,
                icon: const Icon(AppIcons.edit),
                label: Text(hasKeyFile ? 'Change key file' : 'Select key file'),
              );
              final removeButton = OutlinedButton.icon(
                onPressed: onRemove,
                icon: const Icon(AppIcons.close),
                label: const Text('Remove key file'),
              );

              if (stackButtons) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    changeButton,
                    const SizedBox(height: 8),
                    removeButton,
                  ],
                );
              }

              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [changeButton, removeButton],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DatabaseSettingsInfoCallout extends StatelessWidget {
  const _DatabaseSettingsInfoCallout({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colorScheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatabaseSettingsChangesSummary extends StatelessWidget {
  const _DatabaseSettingsChangesSummary({required this.changes});

  final List<String> changes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.tertiaryContainer.withValues(alpha: 0.34),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  AppIcons.check,
                  size: 18,
                  color: colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  'Changes summary',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...changes.map(
              (change) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '•',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onTertiaryContainer,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        change,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onTertiaryContainer,
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
    );
  }
}

// ─── Duplicate badge ──────────────────────────────────────────────────────────

class _DuplicateBadge extends StatelessWidget {
  const _DuplicateBadge({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return child;
    final colorScheme = Theme.of(context).colorScheme;
    return Badge(
      label: Text('$count'),
      backgroundColor: colorScheme.error,
      textColor: colorScheme.onError,
      child: child,
    );
  }
}

// ─── Settings bottom sheet ────────────────────────────────────────────────────

class _VaultSettingsSheet extends StatelessWidget {
  const _VaultSettingsSheet({
    required this.state,
    required this.themeMode,
    required this.canConfigureAndroidAutofill,
    required this.canConfigureBrowserAutofill,
    required this.onSelect,
  });

  final VaultState state;
  final ThemeMode themeMode;
  final bool canConfigureAndroidAutofill;
  final bool canConfigureBrowserAutofill;
  final Future<void> Function(String) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.88;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return SafeArea(
      minimum: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.6,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      AppIcons.settings,
                      size: 17,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Settings',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Google Drive ──────────────────────────────────────
                    _SheetSection(
                      label: 'Google Drive',
                      icon: AppIcons.cloud,
                      iconColor: colorScheme.primary,
                      children: [
                        if (!state.isDriveConnected)
                          _SheetItem(
                            icon: AppIcons.cloud,
                            iconContainerColor: colorScheme.primaryContainer
                                .withValues(alpha: 0.6),
                            iconColor: colorScheme.onPrimaryContainer,
                            label: 'Connect Google Drive',
                            subtitle: 'Enable cloud backup and sync',
                            onTap: () => onSelect('connect'),
                          )
                        else if (!state.isDriveLinked)
                          _SheetItem(
                            icon: AppIcons.linkSimple,
                            iconContainerColor: colorScheme.primaryContainer
                                .withValues(alpha: 0.6),
                            iconColor: colorScheme.onPrimaryContainer,
                            label: 'Link database to Drive',
                            subtitle: 'Choose a .kdbx file to sync with',
                            onTap: () => onSelect('link'),
                          ),
                        _SheetToggleItem(
                          icon: AppIcons.sync,
                          iconContainerColor:
                              state.isDriveConnected && state.isDriveLinked
                              ? colorScheme.secondaryContainer.withValues(
                                  alpha: 0.7,
                                )
                              : colorScheme.surfaceContainerHighest,
                          iconColor:
                              state.isDriveConnected && state.isDriveLinked
                              ? colorScheme.onSecondaryContainer
                              : colorScheme.onSurface.withValues(alpha: 0.38),
                          label: 'Auto-sync',
                          subtitle:
                              state.isDriveConnected && state.isDriveLinked
                              ? 'Sync automatically when the vault changes'
                              : 'Connect and link Drive first',
                          value: state.autoSyncEnabled,
                          enabled:
                              state.isDriveConnected && state.isDriveLinked,
                          onChanged: (_) => onSelect('toggleAutoSync'),
                        ),
                        if (state.isDriveConnected)
                          _SheetItem(
                            icon: AppIcons.cloudOff,
                            iconContainerColor: colorScheme.errorContainer
                                .withValues(alpha: 0.42),
                            iconColor: colorScheme.error,
                            label: 'Disconnect Google Drive',
                            labelColor: colorScheme.error,
                            onTap: () => onSelect('disconnect'),
                          ),
                      ],
                    ),
                    const _SheetDivider(),

                    // ── Vault ─────────────────────────────────────────────
                    _SheetSection(
                      label: 'Vault',
                      icon: AppIcons.key,
                      iconColor: colorScheme.secondary,
                      children: [
                        _SheetItem(
                          icon: AppIcons.settings,
                          iconContainerColor: colorScheme.secondaryContainer
                              .withValues(alpha: 0.6),
                          iconColor: colorScheme.onSecondaryContainer,
                          label: 'Database settings',
                          subtitle: 'Password, key file, biometrics',
                          onTap: () => onSelect('databaseSettings'),
                        ),
                        _SheetItem(
                          icon: AppIcons.folderCopy,
                          iconContainerColor: colorScheme.secondaryContainer
                              .withValues(alpha: 0.6),
                          iconColor: colorScheme.onSecondaryContainer,
                          label: 'Change database',
                          subtitle: 'Switch to a different .kdbx file',
                          onTap: () => onSelect('changeDatabase'),
                        ),
                        _SheetItem(
                          icon: AppIcons.lock,
                          iconContainerColor: colorScheme.tertiaryContainer
                              .withValues(alpha: 0.6),
                          iconColor: colorScheme.onTertiaryContainer,
                          label: 'Lock vault',
                          subtitle: 'Require password to access again',
                          onTap: () => onSelect('lockVault'),
                        ),
                      ],
                    ),
                    const _SheetDivider(),

                    // ── Tools ─────────────────────────────────────────────
                    _SheetSection(
                      label: 'Tools',
                      icon: AppIcons.fileText,
                      iconColor: colorScheme.tertiary,
                      children: [
                        _SheetItem(
                          icon: AppIcons.magic,
                          iconContainerColor: colorScheme.tertiaryContainer
                              .withValues(alpha: 0.55),
                          iconColor: colorScheme.onTertiaryContainer,
                          label: 'Password generator',
                          subtitle: 'Generate and copy a strong password',
                          onTap: () => onSelect('passwordGenerator'),
                        ),
                        _SheetItem(
                          icon: AppIcons.import,
                          iconContainerColor: colorScheme.tertiaryContainer
                              .withValues(alpha: 0.55),
                          iconColor: colorScheme.onTertiaryContainer,
                          label: 'Import from CSV',
                          subtitle: 'Add records from a spreadsheet export',
                          onTap: () => onSelect('importCsv'),
                        ),
                        _SheetItem(
                          icon: AppIcons.export,
                          iconContainerColor: colorScheme.tertiaryContainer
                              .withValues(alpha: 0.55),
                          iconColor: colorScheme.onTertiaryContainer,
                          label: 'Export database backup',
                          subtitle: 'Save a copy of the .kdbx file',
                          onTap: () => onSelect('exportDatabaseBackup'),
                        ),
                        _SheetItem(
                          icon: AppIcons.fileKey,
                          iconContainerColor: colorScheme.tertiaryContainer
                              .withValues(alpha: 0.55),
                          iconColor: colorScheme.onTertiaryContainer,
                          label: 'Export key file',
                          subtitle: 'Back up the key file to a safe location',
                          onTap: () => onSelect('exportKeyFile'),
                        ),
                        _SheetItem(
                          icon: AppIcons.delete,
                          iconContainerColor:
                              colorScheme.surfaceContainerHighest,
                          iconColor: colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                          label: 'Recycle bin',
                          subtitle: 'View and restore deleted records',
                          onTap: () => onSelect('recycleBin'),
                        ),
                        _SheetItem(
                          icon: AppIcons.copy,
                          iconContainerColor: state.duplicateGroupCount > 0
                              ? colorScheme.tertiaryContainer.withValues(
                                  alpha: 0.6,
                                )
                              : colorScheme.surfaceContainerHighest,
                          iconColor: state.duplicateGroupCount > 0
                              ? colorScheme.onTertiaryContainer
                              : colorScheme.onSurface.withValues(alpha: 0.7),
                          label: 'Manage duplicates',
                          subtitle: state.duplicateGroupCount > 0
                              ? '${state.duplicateGroupCount} group${state.duplicateGroupCount == 1 ? '' : 's'} detected'
                              : 'Merge or remove duplicate entries',
                          onTap: () => onSelect('manageDuplicates'),
                        ),
                        if (canConfigureAndroidAutofill)
                          _SheetItem(
                            icon: AppIcons.fingerprint,
                            iconContainerColor: colorScheme.secondaryContainer
                                .withValues(alpha: 0.6),
                            iconColor: colorScheme.onSecondaryContainer,
                            label: 'Android autofill',
                            subtitle: 'Fill passwords in apps and browsers',
                            onTap: () => onSelect('androidAutofill'),
                          ),
                        if (canConfigureBrowserAutofill)
                          _SheetItem(
                            icon: AppIcons.globe,
                            iconContainerColor: colorScheme.secondaryContainer
                                .withValues(alpha: 0.6),
                            iconColor: colorScheme.onSecondaryContainer,
                            label: 'Desktop browser extension',
                            subtitle:
                                'Install and connect the desktop browser host',
                            onTap: () => onSelect('browserSetup'),
                          ),
                      ],
                    ),
                    const _SheetDivider(),

                    // ── Appearance ────────────────────────────────────────
                    _SheetSection(
                      label: 'Appearance',
                      icon: AppIcons.sun,
                      iconColor: colorScheme.tertiary,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                          child: _ThemePicker(
                            themeMode: themeMode,
                            onSelect: (mode) {
                              switch (mode) {
                                case ThemeMode.system:
                                  onSelect('themeSystem');
                                case ThemeMode.light:
                                  onSelect('themeLight');
                                case ThemeMode.dark:
                                  onSelect('themeDark');
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetSection extends StatelessWidget {
  const _SheetSection({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.children,
  });

  final String label;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Row(
            children: [
              Icon(icon, size: 13, color: iconColor),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: colorScheme.onSurface.withValues(alpha: 0.52),
                ),
              ),
            ],
          ),
        ),
        ...children,
      ],
    );
  }
}

class _SheetDivider extends StatelessWidget {
  const _SheetDivider();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      indent: 20,
      endIndent: 20,
      color: colorScheme.outlineVariant.withValues(alpha: 0.45),
    );
  }
}

class _SheetItem extends StatelessWidget {
  const _SheetItem({
    required this.icon,
    required this.iconContainerColor,
    required this.iconColor,
    required this.label,
    this.subtitle,
    this.labelColor,
    this.onTap,
  });

  final IconData icon;
  final Color iconContainerColor;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final Color? labelColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconContainerColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 17, color: iconColor),
      ),
      title: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: labelColor,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.58),
              ),
            )
          : null,
    );
  }
}

class _SheetToggleItem extends StatelessWidget {
  const _SheetToggleItem({
    required this.icon,
    required this.iconContainerColor,
    required this.iconColor,
    required this.label,
    this.subtitle,
    required this.value,
    this.enabled = true,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconContainerColor;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveAlpha = enabled ? 1.0 : 0.5;

    return SwitchListTile.adaptive(
      value: value,
      onChanged: enabled ? onChanged : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      secondary: Opacity(
        opacity: effectiveAlpha,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconContainerColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: iconColor),
        ),
      ),
      title: Opacity(
        opacity: effectiveAlpha,
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      subtitle: subtitle != null
          ? Opacity(
              opacity: effectiveAlpha,
              child: Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.58),
                ),
              ),
            )
          : null,
    );
  }
}

class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.themeMode, required this.onSelect});

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget option(ThemeMode mode, IconData icon, String label) {
      final selected = themeMode == mode;
      return Expanded(
        child: GestureDetector(
          onTap: () => onSelect(mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? colorScheme.primaryContainer.withValues(alpha: 0.76)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? colorScheme.primary.withValues(alpha: 0.5)
                    : colorScheme.outlineVariant.withValues(alpha: 0.55),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface.withValues(alpha: 0.62),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        option(ThemeMode.system, AppIcons.desktop, 'System'),
        const SizedBox(width: 8),
        option(ThemeMode.light, AppIcons.sun, 'Light'),
        const SizedBox(width: 8),
        option(ThemeMode.dark, AppIcons.moon, 'Dark'),
      ],
    );
  }
}
