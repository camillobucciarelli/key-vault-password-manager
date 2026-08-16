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
  const _VaultSettingsDestination({required this.onCloseDatabase});

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
    }
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

const _kApplicationName = 'Antigravity Password Manager';

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
