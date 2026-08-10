import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_glyph.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/keyvault_colors.dart';
import '../../../../core/widgets/kv_icon.dart';
import '../../../../core/widgets/kv_pill_button.dart';
import 'browser_setup_screen.dart';

/// FR-4/T6 — screen 6 ("iOS autofill enablement", mock: "Autofill &
/// browsers" onboarding). The three system steps plus an explicit "what is
/// shared" statement.
///
/// AC8 / spec-006 risk mitigation: the human confirmed (see the task
/// report) that the claim in tasks.md/spec.md — "titles, usernames and
/// sites — not passwords" — does **not** match what
/// `AppleAutofillV2Coordinator.publishVault` actually sends: reading
/// `AppleAutofillV2Credential.toChannelMap()` (the payload published to
/// `SharedAutofillStore` via the `apple_autofill_v2` method channel — see
/// `ios/CredentialProviderExtension/SharedAutofillStore.swift` and
/// `AppleAutofillV2Channel.swift`, which requires `entry.password`) shows
/// the password *is* part of the payload — it has to be, so the
/// Credential Provider extension can actually fill it. [sharedFieldKeys]
/// is kept in lock-step with that payload (see
/// `apple_autofill_v2_enablement_claim_test.dart`) so this screen's copy
/// can never silently drift from reality again.
class AutofillEnablementScreen extends StatelessWidget {
  const AutofillEnablementScreen({super.key, this.entryCount = 0});

  /// Defaults to 0 so the screen can be golden-tested without a `VaultBloc`
  /// in scope; the real call site (`_VaultSettingsDestination`) passes
  /// `context.read<VaultBloc>().state.allEntries.length`.
  final int entryCount;

  /// AC8: every key `AppleAutofillV2Credential.toChannelMap()` publishes
  /// for one credential. Kept exactly equal to that payload's key set (see
  /// `apple_autofill_v2_enablement_claim_test.dart`) — `id` is an internal
  /// record identifier, not sensitive on its own, but is still listed so
  /// this stays a *complete* inventory rather than a hand-picked subset
  /// that could quietly stop noticing a new field.
  @visibleForTesting
  static const sharedFieldKeys = <String>{
    'id',
    'title',
    'username',
    'password',
    'url',
    'serviceIdentifiers',
  };

  Future<void> _openIosSettings(BuildContext context) async {
    await launchUrl(Uri.parse('app-settings:'));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;

    return Scaffold(
      backgroundColor: colors.ground,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
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
                    'Autofill & browsers',
                    style: AppTextStyles.panelTitle.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: colors.attentionTint,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: colors.actionFill,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: KvIcon(
                                  glyph: AppGlyph.desktop,
                                  size: 20,
                                  color: colors.actionText,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Not enabled yet',
                                      style: AppTextStyles.rowTitle.copyWith(
                                        color: colors.attentionText,
                                      ),
                                    ),
                                    Text(
                                      'iOS asks you once, in Settings',
                                      style: AppTextStyles.metaLarge.copyWith(
                                        color: colors.attentionText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _EnablementStep(
                            number: 1,
                            text: 'Settings → General → AutoFill & Passwords',
                          ),
                          const SizedBox(height: 8),
                          _EnablementStep(
                            number: 2,
                            text: 'Turn on AutoFill Passwords',
                          ),
                          const SizedBox(height: 8),
                          _EnablementStep(
                            number: 3,
                            text: 'Pick KeyVault in the list',
                          ),
                          const SizedBox(height: 14),
                          KvPillButton(
                            label: 'Open iOS settings',
                            compact: true,
                            onPressed: () => _openIosSettings(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
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
                              color: colors.surfaceNested,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: KvIcon(
                              glyph: AppGlyph.fileText,
                              size: 19,
                              color: colors.iconNeutral,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Entries shared with AutoFill',
                                  style: AppTextStyles.rowTitle.copyWith(
                                    color: colors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$entryCount titles, usernames and sites. '
                                  'An encrypted copy of each password is also '
                                  'kept on this device and revealed only when '
                                  'you pick a credential and confirm with '
                                  'Face ID.',
                                  style: AppTextStyles.metaLarge.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (BrowserSetupScreen.shouldShow)
                      _DesktopBrowsersRow(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const BrowserSetupScreen(),
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    Text(
                      'KeyVault never fills a field without you choosing the '
                      'record first.',
                      style: AppTextStyles.meta.copyWith(
                        color: colors.textSecondary,
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

class _EnablementStep extends StatelessWidget {
  const _EnablementStep({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.surfaceNested,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: AppTextStyles.labelMicro.copyWith(
              color: colors.attentionText,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.body.copyWith(color: colors.attentionText),
          ),
        ),
      ],
    );
  }
}

class _DesktopBrowsersRow extends StatelessWidget {
  const _DesktopBrowsersRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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
                child: KvIcon(
                  glyph: AppGlyph.desktop,
                  size: 19,
                  color: colors.iconNeutral,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Desktop browsers',
                      style: AppTextStyles.rowTitle.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      'Set up on your Mac or PC',
                      style: AppTextStyles.metaLarge.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              KvIcon(
                glyph: AppGlyph.chevronRight,
                size: 17,
                color: colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
