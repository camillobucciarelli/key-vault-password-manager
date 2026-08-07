import 'package:flutter/material.dart';

import '../../../../../core/theme/app_glyph.dart';
import '../../../../../core/theme/app_motion.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/keyvault_colors.dart';
import '../../../../../core/widgets/kv_icon.dart';

/// Revealed-password row (spec-004 FR-2, PIXEL_SPEC "Entry detail"):
/// `attentionTint` background, monospace 16 with word-break, 4 px countdown
/// bar draining as [remainingFraction] falls. The *bar's* width transition
/// respects `AppMotion`/reduced motion; the underlying 12 s expiry timer
/// (owned by [RevealController], not this widget) is a security control and
/// is never itself disabled by reduced motion.
class RevealedPasswordRow extends StatelessWidget {
  const RevealedPasswordRow({
    super.key,
    required this.password,
    required this.remainingFraction,
    required this.remainingSeconds,
    required this.onHide,
    this.onCopy,
  });

  final String password;
  final double remainingFraction;
  final int remainingSeconds;
  final VoidCallback onHide;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    // The bar steps once per second (shared ticker, see RevealController's
    // doc comment); this only smooths that per-second step visually and is
    // zeroed under reduced motion. It never affects the 12s expiry itself.
    final barDuration = AppMotion.duration(context, const Duration(seconds: 1));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: colors.attentionTint,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Password · visible for ${remainingSeconds}s',
                      style: AppTextStyles.labelUpper.copyWith(
                        color: colors.attentionText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      password,
                      style: AppTextStyles.secretLarge.copyWith(
                        color: colors.attentionText,
                      ),
                    ),
                  ],
                ),
              ),
              if (onCopy != null) ...[
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    tooltip: 'Copy',
                    onPressed: onCopy,
                    style: IconButton.styleFrom(
                      backgroundColor: colors.actionFill,
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                    ),
                    icon: KvIcon(
                      glyph: AppGlyph.copy,
                      size: 17,
                      color: colors.actionText,
                    ),
                  ),
                ),
              ],
              SizedBox(
                width: 36,
                height: 36,
                child: IconButton(
                  tooltip: 'Hide password',
                  onPressed: onHide,
                  style: IconButton.styleFrom(
                    backgroundColor: colors.actionFill,
                    shape: const CircleBorder(),
                    padding: EdgeInsets.zero,
                  ),
                  icon: KvIcon(
                    glyph: AppGlyph.eyeOff,
                    size: 17,
                    color: colors.actionText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 4,
              color: colors.actionFill,
              child: Align(
                alignment: Alignment.centerLeft,
                child: TweenAnimationBuilder<double>(
                  duration: barDuration,
                  tween: Tween<double>(end: remainingFraction.clamp(0.0, 1.0)),
                  builder: (context, factor, child) =>
                      FractionallySizedBox(widthFactor: factor, child: child),
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: colors.actionEmphasis),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
