import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_glyph.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/keyvault_colors.dart';
import '../../../../core/widgets/kv_bottom_sheet.dart';
import '../../../../core/widgets/kv_icon.dart';
import '../../../../core/widgets/kv_pill_button.dart';
import '../../../../injection_container.dart' as di;
import '../../domain/utils/password_strength.dart';
import '../coordinators/vault_session_coordinator.dart';

/// FR-2/T3 — screen 2 ("Change master password"). The three real fields
/// are unchanged from the legacy `Database settings` dialog's password
/// section (current / new / confirm); submitting opens the `Confirm
/// security changes` → `Confirm and apply` sheet (screen 3, T3) before
/// calling `VaultSessionCoordinator.updateDatabaseSettings` with
/// `changePassword: true` — the same coordinator method the legacy dialog
/// used, which now also writes the constitution-VII dated pre-rekey backup
/// (see `VaultSessionCoordinator._writeDatedPreRekeyBackup`).
class ChangeMasterPasswordScreen extends StatefulWidget {
  const ChangeMasterPasswordScreen({super.key, required this.databasePath});

  final String databasePath;

  @override
  State<ChangeMasterPasswordScreen> createState() =>
      _ChangeMasterPasswordScreenState();
}

class _ChangeMasterPasswordScreenState
    extends State<ChangeMasterPasswordScreen> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _saving = false;
  bool _loaded = false;
  String? _keyFilePath;
  bool _biometricEnabled = false;
  int? _inactivityTimeoutSeconds;
  String? _error;

  @override
  void initState() {
    super.initState();
    _newCtrl.addListener(() => setState(() {}));
    _confirmCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final coordinator = di.sl<VaultSessionCoordinator>();
    final keyFilePath = await coordinator.getPersistedKeyFilePath(
      widget.databasePath,
    );
    final biometricEnabled = await coordinator
        .getBiometricProtectionEnabledForPath(
          databasePath: widget.databasePath,
        );
    final inactivityTimeoutSeconds = await coordinator
        .getInactivityLockTimeoutForPath(databasePath: widget.databasePath);
    if (!mounted) return;
    setState(() {
      _keyFilePath = keyFilePath;
      _biometricEnabled = biometricEnabled;
      _inactivityTimeoutSeconds = inactivityTimeoutSeconds;
      _loaded = true;
    });
  }

  bool get _canSubmit =>
      _loaded &&
      !_saving &&
      _newCtrl.text.isNotEmpty &&
      _newCtrl.text == _confirmCtrl.text;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final confirmed = await KvBottomSheet.show<bool>(
      context: context,
      builder: (_) => _ConfirmSecurityChangesSheet(
        keyFileLabel: _keyFilePath == null || _keyFilePath!.trim().isEmpty
            ? 'Key file · none'
            : 'Key file · ${path.basename(_keyFilePath!)}',
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await di.sl<VaultSessionCoordinator>().updateDatabaseSettings(
        DatabaseSettingsUpdateRequest(
          currentDatabasePath: widget.databasePath,
          fileName: path.basename(widget.databasePath),
          keyFilePath: _keyFilePath,
          biometricProtectionEnabled: _biometricEnabled,
          changePassword: true,
          inactivityLockTimeoutSeconds: _inactivityTimeoutSeconds,
          currentPassword: _currentCtrl.text,
          newPassword: _newCtrl.text,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Unable to change the master password. Check the current '
              'password and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    final assessment = evaluatePasswordStrength(_newCtrl.text);

    return Scaffold(
      backgroundColor: colors.ground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: IconButton(
                      tooltip: 'Back',
                      onPressed: () => Navigator.maybePop(context),
                      style: IconButton.styleFrom(
                        backgroundColor: colors.surface,
                        shape: const CircleBorder(),
                        padding: EdgeInsets.zero,
                      ),
                      icon: KvIcon(
                        glyph: AppGlyph.back,
                        size: 18,
                        color: colors.iconNeutral,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Change master password',
                    style: AppTextStyles.panelTitle.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _PasswordFieldRow(
                label: 'Current master password',
                controller: _currentCtrl,
              ),
              const SizedBox(height: 14),
              _PasswordFieldRow(
                label: 'New master password',
                controller: _newCtrl,
                highlighted: true,
              ),
              if (_newCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 8),
                _StrengthBar(assessment: assessment),
              ],
              const SizedBox(height: 14),
              _PasswordFieldRow(
                label: 'Confirm new password',
                controller: _confirmCtrl,
                trailingCheck:
                    _confirmCtrl.text.isNotEmpty &&
                    _confirmCtrl.text == _newCtrl.text,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: colors.attentionTint,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KvIcon(
                      glyph: AppGlyph.warning,
                      size: 17,
                      color: colors.attentionText,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Devices with the old password will refuse to open '
                        'this file after the next sync. Update them, or '
                        'export a backup first.',
                        style: AppTextStyles.secondary.copyWith(
                          color: colors.attentionText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: AppTextStyles.secondary.copyWith(
                    color: colors.attentionText,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              KvPillButton(
                label: _saving ? 'Saving…' : 'Save changes',
                onPressed: _canSubmit ? _submit : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordFieldRow extends StatelessWidget {
  const _PasswordFieldRow({
    required this.label,
    required this.controller,
    this.highlighted = false,
    this.trailingCheck = false,
  });

  final String label;
  final TextEditingController controller;
  final bool highlighted;
  final bool trailingCheck;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.labelUpper.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(22),
            border: highlighted
                ? Border.all(color: colors.selectionBorder, width: 2)
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: AppTextStyles.fieldValue.copyWith(
                    color: colors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              if (trailingCheck)
                KvIcon(
                  glyph: AppGlyph.check,
                  size: 18,
                  color: colors.positiveText,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StrengthBar extends StatelessWidget {
  const _StrengthBar({required this.assessment});

  final PasswordStrengthAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    final filled = switch (assessment.level) {
      PasswordStrengthLevel.weak => 1,
      PasswordStrengthLevel.fair => 2,
      PasswordStrengthLevel.good => 3,
      PasswordStrengthLevel.strong => 4,
    };
    final activeColor = assessment.level == PasswordStrengthLevel.strong
        ? colors.positiveFill
        : AppColors.accent400;

    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: i < filled ? activeColor : colors.divider,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ],
        const SizedBox(width: 8),
        Text(
          assessment.label,
          style: AppTextStyles.metaLarge.copyWith(
            color: colors.positiveText,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// FR-2/T3 — screen 3 ("Confirm security changes" sheet). Lists what
/// changes (always "Master password" here — this sheet only opens from the
/// change-password submit) and what stays (key file, biometrics, Drive
/// link, entries — none of those are touched by a password-only re-key).
class _ConfirmSecurityChangesSheet extends StatelessWidget {
  const _ConfirmSecurityChangesSheet({required this.keyFileLabel});

  final String keyFileLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(height: 16),
          Text(
            'Confirm security changes',
            style: AppTextStyles.sheetTitle.copyWith(
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'The file will be re-encrypted with the new master password. A '
            'dated backup of the current file is kept automatically. This '
            "cannot be undone from inside the app.",
            style: AppTextStyles.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 14),
          _ChangeRow(
            tag: 'Change',
            tagBackground: colors.attentionTint,
            tagColor: colors.attentionText,
            label: 'Master password',
          ),
          const SizedBox(height: 8),
          _ChangeRow(
            tag: 'Keep',
            tagBackground: colors.surfaceNested,
            tagColor: colors.textSecondary,
            label: keyFileLabel,
            dimmed: true,
          ),
          const SizedBox(height: 8),
          _ChangeRow(
            tag: 'Keep',
            tagBackground: colors.surfaceNested,
            tagColor: colors.textSecondary,
            label: 'Biometric protection · Drive link · entries',
            dimmed: true,
          ),
          const SizedBox(height: 18),
          KvPillButton(
            label: 'Confirm and apply',
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: 9),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.textPrimary,
                side: BorderSide(color: colors.divider),
                minimumSize: const Size(44, 52),
                shape: const StadiumBorder(),
                textStyle: AppTextStyles.rowTitle,
              ),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({
    required this.tag,
    required this.tagBackground,
    required this.tagColor,
    required this.label,
    this.dimmed = false,
  });

  final String tag;
  final Color tagBackground;
  final Color tagColor;
  final String label;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return Opacity(
      opacity: dimmed ? 0.7 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: tagBackground,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                tag,
                style: AppTextStyles.labelMicro.copyWith(color: tagColor),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.secondary.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
