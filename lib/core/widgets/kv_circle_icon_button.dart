import 'package:flutter/material.dart';

import '../theme/app_glyph.dart';
import '../theme/keyvault_colors.dart';
import 'kv_icon.dart';

/// The design's circular icon button: a 36 px surface-filled circle holding
/// one glyph, with a mandatory tooltip.
///
/// One recipe for every host — detail header, field-row trailing actions,
/// dialog chrome — instead of each screen hand-rolling the same
/// `IconButton.styleFrom(shape: CircleBorder(), ...)` block.
class KvCircleIconButton extends StatelessWidget {
  const KvCircleIconButton({
    super.key,
    required this.glyph,
    required this.tooltip,
    required this.onPressed,
    this.nested = false,
    this.size = 36,
    this.iconSize = 19,
  });

  final AppGlyph glyph;
  final String tooltip;
  final VoidCallback? onPressed;

  /// True where the button sits on a surface already (a field row): it fills
  /// with `surfaceNested` instead of `surface` so it still reads as raised.
  final bool nested;

  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KeyVaultColors>()!;
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: nested ? colors.surfaceNested : colors.surface,
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
        icon: KvIcon(glyph: glyph, size: iconSize, color: colors.iconNeutral),
      ),
    );
  }
}
