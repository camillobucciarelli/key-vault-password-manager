part of '../vault_screen.dart';

/// Test-only clock seam: TOTP codes and countdowns are wall-clock-real by
/// design (they must be), which makes them inherently non-deterministic for
/// pixel goldens. Golden tests set this to a fixed `DateTime.now`
/// replacement before pumping and reset it in `tearDown`; production code
/// never touches it.
@visibleForTesting
DateTime Function() debugEntryDetailNowOverride = DateTime.now;

/// FR-1/FR-2/FR-4 (spec-004): entry detail screen (mobile push) / pane
/// (tablet, via `VaultShellRouter`'s existing pane presentation — no route
/// is pushed on tablet, see `VaultShellRouter.presentationFor`).
class _EntryDetailsPage extends StatelessWidget {
  const _EntryDetailsPage({required this.entryId, this.onSelectedAction});

  final String entryId;
  final ValueChanged<_EntryAction>? onSelectedAction;

  @override
  Widget build(BuildContext context) {
    final entry = context.select((VaultBloc bloc) {
      for (final e in bloc.state.allEntries) {
        if (e.id == entryId) return e;
      }
      return null;
    });

    if (entry == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
      return const SizedBox.shrink();
    }

    return DecoratedBox(
      decoration: BoxDecoration(gradient: AppBackgrounds.gradient(context)),
      child: _EntryDetailPanel(
        entry: entry,
        onSelectedAction: onSelectedAction,
        allowsPop: true,
      ),
    );
  }
}

class _EntryDetailPanel extends StatefulWidget {
  const _EntryDetailPanel({
    required this.entry,
    this.onSelectedAction,
    this.allowsPop = false,
  });

  final VaultEntry entry;
  final ValueChanged<_EntryAction>? onSelectedAction;

  /// True when hosted as a pushed route (mobile): the header's back chevron
  /// pops. False when hosted inline (tablet list column, or the tablet
  /// detail pane, which already has its own generic back affordance) — the
  /// chevron is hidden rather than risk popping an unrelated route.
  final bool allowsPop;

  @override
  State<_EntryDetailPanel> createState() => _EntryDetailPanelState();
}

class _EntryDetailPanelState extends State<_EntryDetailPanel> {
  // Single shared 1s ticker driving both the TOTP countdown and the reveal
  // countdown bar (spec-004 "TOTP + reveal" non-negotiable) — not two
  // independent timers.
  Timer? _ticker;
  DateTime _nowUtc = debugEntryDetailNowOverride().toUtc();
  late final RevealController _revealController;
  bool _isCheckingBiometrics = false;

  @override
  void initState() {
    super.initState();
    _revealController = RevealController()..addListener(_onRevealChanged);
    _configureTicker();
  }

  @override
  void didUpdateWidget(covariant _EntryDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.id != widget.entry.id) {
      _revealController.hide();
    }
    _configureTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _revealController.removeListener(_onRevealChanged);
    _revealController.dispose();
    super.dispose();
  }

  void _onRevealChanged() {
    if (mounted) setState(() {});
  }

  void _configureTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _nowUtc = debugEntryDetailNowOverride().toUtc());
      _revealController.tick();
    });
  }

  Future<void> _copy({required String text, required String message}) async {
    if (text.isEmpty) return;
    await di.sl<ClipboardGuard>().copy(text);
    if (!mounted) return;
    _showCenteredCopyToast(context, message);
  }

  Future<void> _handleRevealTap(String databasePath) async {
    if (_revealController.isRevealed) {
      _revealController.hide();
      return;
    }
    if (_isCheckingBiometrics) return;
    setState(() => _isCheckingBiometrics = true);
    bool biometricEnabled;
    try {
      biometricEnabled = await di
          .sl<VaultSessionCoordinator>()
          .getBiometricProtectionEnabledForPath(databasePath: databasePath);
    } catch (_) {
      biometricEnabled = false;
    }
    if (!mounted) return;
    setState(() => _isCheckingBiometrics = false);

    if (!biometricEnabled) {
      _revealController.reveal();
      return;
    }

    final unlocked = await _showBiometricRevealGate(context, databasePath);
    if (unlocked == true && mounted) {
      _revealController.reveal();
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= Breakpoints.mobile;
    final databasePath = context.read<VaultBloc>().state.databasePath;

    final title = entry.title.isEmpty ? '(Untitled)' : entry.title;
    final folderName = _folderNameFor(context, entry.groupId);
    final subtitle = entry.url.isEmpty
        ? folderName
        : '$folderName · ${_hostFor(entry.url)}';

    final customFields = entry.customFields
        .where((field) => !_isOtpFieldKey(field.key))
        .toList(growable: false);
    final totpData = entry.otpUri == null
        ? null
        : TotpUtils.fromOtpAuthUri(entry.otpUri!, _nowUtc);
    final strength = evaluatePasswordStrength(entry.password);
    final reusedByCount = entry.password.isEmpty
        ? 0
        : context.read<VaultBloc>().state.allEntries.where((other) {
            return other.id != entry.id && other.password == entry.password;
          }).length;
    final isWarning =
        entry.password.isNotEmpty &&
        (strength.level == PasswordStrengthLevel.weak || reusedByCount > 0);
    final changedAgo = describeTimeAgo(
      entry.lastPasswordChangedAt,
      debugEntryDetailNowOverride(),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DetailHeader(
              allowsPop: widget.allowsPop,
              onEdit: widget.onSelectedAction == null
                  ? null
                  : () => widget.onSelectedAction!(_EntryAction.edit),
              onMore: widget.onSelectedAction,
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KvLetterAvatar(letter: title, size: 56, fontSize: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.screenTitle.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            KvFieldRow(
              label: 'Username',
              value: entry.username.isEmpty
                  ? 'Username not set'
                  : entry.username,
              onCopy: entry.username.isEmpty
                  ? null
                  : () => _copy(
                      text: entry.username,
                      message: 'Copied username.',
                    ),
            ),
            const SizedBox(height: 9),
            if (entry.password.isEmpty)
              const KvFieldRow(label: 'Password', value: 'Password not set')
            else if (_revealController.isRevealed)
              RevealedPasswordRow(
                password: entry.password,
                remainingFraction: _revealController.remainingFraction,
                remainingSeconds:
                    (RevealController.revealSeconds *
                            _revealController.remainingFraction)
                        .ceil(),
                onHide: () => _handleRevealTap(databasePath),
                onCopy: () =>
                    _copy(text: entry.password, message: 'Copied password.'),
              )
            else
              KvFieldRow(
                label: 'Password',
                value: '••••••••••••',
                onCopy: () =>
                    _copy(text: entry.password, message: 'Copied password.'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: IconButton(
                        tooltip: 'Show password',
                        onPressed: _isCheckingBiometrics
                            ? null
                            : () => _handleRevealTap(databasePath),
                        style: IconButton.styleFrom(
                          backgroundColor: colors.surfaceNested,
                          shape: const CircleBorder(),
                          padding: EdgeInsets.zero,
                        ),
                        icon: KvIcon(
                          glyph: AppGlyph.eye,
                          size: 17,
                          color: colors.iconNeutral,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: IconButton(
                        tooltip: 'Copy',
                        onPressed: () => _copy(
                          text: entry.password,
                          message: 'Copied password.',
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: colors.surfaceNested,
                          shape: const CircleBorder(),
                          padding: EdgeInsets.zero,
                        ),
                        icon: KvIcon(
                          glyph: AppGlyph.copy,
                          size: 17,
                          color: colors.iconNeutral,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (totpData != null) ...[
              const SizedBox(height: 9),
              TotpRow(
                data: totpData,
                onCopy: () => _copy(
                  text: totpData.code,
                  message: 'Copied one-time code.',
                ),
              ),
            ],
            if (entry.url.isNotEmpty) ...[
              const SizedBox(height: 9),
              KvFieldRow(
                label: 'Website',
                value: entry.url,
                valueColor: colors.linkText,
                onCopy: () => _copy(text: entry.url, message: 'Copied URL.'),
              ),
            ],
            if (entry.notes.isNotEmpty) ...[
              const SizedBox(height: 9),
              KvFieldRow(
                label: 'Notes',
                value: entry.notes,
                maxLines: 4,
                showCopyButton: false,
                onCopy: () =>
                    _copy(text: entry.notes, message: 'Copied notes.'),
              ),
            ],
            if (entry.attachments.isNotEmpty || customFields.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'More',
                style: AppTextStyles.labelUpper.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (entry.attachments.isNotEmpty)
                    _MoreChip(
                      icon: AppGlyph.attachment,
                      label:
                          '${entry.attachments.length} attachment${entry.attachments.length == 1 ? '' : 's'}',
                      onTap: widget.onSelectedAction == null
                          ? null
                          : () => widget.onSelectedAction!(
                              _EntryAction.attachments,
                            ),
                    ),
                  if (customFields.isNotEmpty)
                    _MoreChip(
                      icon: AppGlyph.rowsDiff,
                      label:
                          '${customFields.length} custom field${customFields.length == 1 ? '' : 's'}',
                      onTap: () =>
                          _showCustomFieldsSheet(context, customFields, _copy),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            if (isWarning)
              StrengthStrip.warning(
                assessment: strength,
                changedAgoLabel: changedAgo,
                reusedByCount: reusedByCount,
                onGenerateNew: entry.password.isEmpty
                    ? null
                    : () => _openGeneratorForEntry(context, entry),
              )
            else
              StrengthStrip.normal(
                assessment: strength,
                changedAgoLabel: changedAgo,
              ),
            const SizedBox(height: 10),
            if (isWide)
              Row(
                children: [
                  Expanded(
                    child: _CopyPill(
                      label: 'Copy password',
                      primary: true,
                      onTap: entry.password.isEmpty
                          ? null
                          : () => _copy(
                              text: entry.password,
                              message: 'Copied password.',
                            ),
                    ),
                  ),
                  if (entry.username.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CopyPill(
                        label: 'Copy username',
                        primary: false,
                        onTap: () => _copy(
                          text: entry.username,
                          message: 'Copied username.',
                        ),
                      ),
                    ),
                  ],
                ],
              )
            else
              KvPillButton(
                label: 'Copy password',
                icon: null,
                onPressed: entry.password.isEmpty
                    ? null
                    : () => _copy(
                        text: entry.password,
                        message: 'Copied password.',
                      ),
              ),
            if (isWide) ...[
              const SizedBox(height: 16),
              const _MetadataGridLabel(),
              const SizedBox(height: 8),
              _MetadataGrid(entry: entry),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.allowsPop,
    required this.onEdit,
    required this.onMore,
  });

  final bool allowsPop;
  final VoidCallback? onEdit;
  final ValueChanged<_EntryAction>? onMore;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;

    Widget circleButton({
      required AppGlyph glyph,
      required String tooltip,
      required VoidCallback? onPressed,
    }) {
      return SizedBox(
        width: 36,
        height: 36,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: colors.surface,
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
          ),
          icon: KvIcon(glyph: glyph, size: 19, color: colors.iconNeutral),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (allowsPop)
          circleButton(
            glyph: AppGlyph.back,
            tooltip: 'Back',
            onPressed: () => Navigator.maybePop(context),
          )
        else
          const SizedBox(width: 36, height: 36),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            circleButton(
              glyph: AppGlyph.edit,
              tooltip: 'Edit',
              onPressed: onEdit,
            ),
            const SizedBox(width: 8),
            PopupMenuButton<_EntryAction>(
              tooltip: 'Record actions',
              onSelected: onMore,
              itemBuilder: (context) => const [
                _RoundedPopupItem(
                  value: _EntryAction.move,
                  child: _MenuItemContent(icon: AppIcons.move, label: 'Move'),
                ),
                _RoundedPopupItem(
                  value: _EntryAction.attachments,
                  child: _MenuItemContent(
                    icon: AppIcons.attachment,
                    label: 'Attachments',
                  ),
                ),
                _RoundedPopupItem(
                  value: _EntryAction.delete,
                  child: _MenuItemContent(
                    icon: AppIcons.delete,
                    label: 'Delete',
                    isDestructive: true,
                  ),
                ),
              ],
              // Plain visual circle, not another `circleButton` (IconButton
              // already carries its own Tooltip): PopupMenuButton wraps
              // `child` in a Tooltip using its own `tooltip` param, and
              // double-nesting two Tooltips on the same hit-test region
              // crashes Flutter's tooltip ticker under widget-test pointer
              // synthesis (observed while adding spec-004's goldens).
              child: SizedBox(
                width: 36,
                height: 36,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: KvIcon(
                      glyph: AppGlyph.more,
                      size: 19,
                      color: colors.iconNeutral,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MoreChip extends StatelessWidget {
  const _MoreChip({required this.icon, required this.label, this.onTap});

  final AppGlyph icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              KvIcon(glyph: icon, size: 16, color: colors.iconNeutral),
              const SizedBox(width: 7),
              Text(
                label,
                style: AppTextStyles.secondary.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CopyPill extends StatelessWidget {
  const _CopyPill({
    required this.label,
    required this.primary,
    required this.onTap,
  });

  final String label;
  final bool primary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return Material(
      color: primary ? colors.actionFill : colors.surface,
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Container(
          height: 46,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            label,
            style: primary
                ? TextStyle(
                    fontFamily: AppTextStyles.headingFamily,
                    fontSize: 14,
                    color: colors.actionText,
                  )
                : AppTextStyles.secondary.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
          ),
        ),
      ),
    );
  }
}

class _MetadataGridLabel extends StatelessWidget {
  const _MetadataGridLabel();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return Text(
      'Record info',
      style: AppTextStyles.labelUpper.copyWith(color: colors.textSecondary),
    );
  }
}

/// Tablet-only metadata grid (spec-004 FR-7/AC8): exactly three rows —
/// Created, Updated, last password change. Not shown on mobile.
class _MetadataGrid extends StatelessWidget {
  const _MetadataGrid({required this.entry});

  final VaultEntry entry;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Created', _formatEntryDateTime(entry.createdAt)),
      ('Updated', _formatEntryDateTime(entry.updatedAt)),
      (
        'Last password change',
        _formatEntryDateTime(entry.lastPasswordChangedAt),
      ),
    ];
    assert(rows.length == 3, 'AC8: metadata grid must show exactly 3 rows.');

    return Column(
      key: const ValueKey('entry-detail-metadata-grid'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          KvFieldRow(label: rows[i].$1, value: rows[i].$2),
        ],
      ],
    );
  }
}

Future<bool?> _showBiometricRevealGate(
  BuildContext context,
  String databasePath,
) {
  return KvBottomSheet.show<bool>(
    context: context,
    builder: (sheetContext) =>
        _BiometricRevealGateSheet(databasePath: databasePath),
  );
}

class _BiometricRevealGateSheet extends StatefulWidget {
  const _BiometricRevealGateSheet({required this.databasePath});

  final String databasePath;

  @override
  State<_BiometricRevealGateSheet> createState() =>
      _BiometricRevealGateSheetState();
}

class _BiometricRevealGateSheetState extends State<_BiometricRevealGateSheet> {
  bool _isAuthenticating = false;

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;
    setState(() => _isAuthenticating = true);
    final ok = await di.sl<BiometricDataSource>().authenticate(
      reason: 'Reveal password',
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _isAuthenticating = false);
  }

  // Reuses the existing whole-vault lock+re-unlock flow — the codebase has
  // no separate "confirm just this reveal with a password" primitive, and
  // spec-004 explicitly asks not to invent new authentication logic.
  Future<void> _usePassword() async {
    final navigatorContext = context;
    Navigator.of(navigatorContext).pop(false);
    await di.sl<VaultSessionCoordinator>().lockVault(
      currentDatabasePath: widget.databasePath,
    );
    if (!navigatorContext.mounted) return;
    AppNavigation.pushFadeReplacement(
      navigatorContext,
      DatabaseUnlockScreen(databasePath: widget.databasePath),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 5,
            decoration: BoxDecoration(
              color: colors.divider,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.actionFill,
              shape: BoxShape.circle,
            ),
            child: KvIcon(
              glyph: AppGlyph.fingerprint,
              size: 25,
              color: colors.actionText,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Confirm it\u2019s you',
            style: AppTextStyles.sheetTitleLarge.copyWith(
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This database requires biometrics before a password is shown '
            'or copied.',
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 14),
          KvPillButton(
            label: 'Unlock with biometrics',
            onPressed: _isAuthenticating ? null : _authenticate,
          ),
          const SizedBox(height: 9),
          KvSecondaryPillButton(label: 'Use password', onPressed: _usePassword),
        ],
      ),
    );
  }
}

Future<void> _showCustomFieldsSheet(
  BuildContext context,
  List<VaultCustomField> fields,
  Future<void> Function({required String text, required String message}) copy,
) {
  return KvBottomSheet.show<void>(
    context: context,
    builder: (sheetContext) {
      final colors = Theme.of(sheetContext).extension<KeyVaultColors>()!;
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 46,
                height: 5,
                decoration: BoxDecoration(
                  color: colors.divider,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Custom fields',
              style: AppTextStyles.sheetTitle.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < fields.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              KvFieldRow(
                label: fields[i].key,
                value: fields[i].value.isEmpty
                    ? 'Value not set'
                    : fields[i].value,
                onCopy: fields[i].value.isEmpty
                    ? null
                    : () => copy(
                        text: fields[i].value,
                        message: 'Copied ${fields[i].key}.',
                      ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

String _folderNameFor(BuildContext context, String groupId) {
  final groups = context.read<VaultBloc>().state.groups;
  for (final group in groups) {
    if (group.id == groupId) return group.name;
  }
  return 'Vault';
}

String _hostFor(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return '';
  final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
  final uri = Uri.tryParse(withScheme);
  final host = uri?.host ?? trimmed;
  return host.isEmpty ? trimmed : host;
}

Future<void> _openGeneratorForEntry(
  BuildContext context,
  VaultEntry entry,
) async {
  await _showPasswordGeneratorSheet(
    context,
    initialOptions: _optionsFromPassword(entry.password),
  );
}

/// FR-4: the weak/reused strip opens the generator "pre-filled with the
/// entry's constraints" — approximated from the current password's
/// character classes and length, clamped to the generator's 8–64 range.
PasswordGeneratorOptions _optionsFromPassword(String password) {
  if (password.isEmpty) {
    return const PasswordGeneratorOptions.defaults();
  }
  final hasLower = password.contains(RegExp('[a-z]'));
  final hasUpper = password.contains(RegExp('[A-Z]'));
  final hasDigit = password.contains(RegExp('[0-9]'));
  final hasSymbol = password.contains(RegExp(r'[^a-zA-Z0-9]'));
  final anySet = hasLower || hasUpper || hasDigit || hasSymbol;
  return PasswordGeneratorOptions(
    length: password.length.clamp(8, 64).toInt(),
    includeLowercase: anySet ? hasLower : true,
    includeUppercase: anySet ? hasUpper : true,
    includeDigits: anySet ? hasDigit : true,
    includeSymbols: anySet ? hasSymbol : true,
  );
}
