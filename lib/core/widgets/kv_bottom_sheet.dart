import 'package:flutter/material.dart';

import '../responsive/breakpoints.dart';

/// Generic typed bottom sheet, extracted from the confirmation/sheet
/// styling `VaultShellRouter._defaultSheetHost` already uses in spec-002
/// (root navigator, scroll-controlled, 560 px max width on tablet/desktop,
/// radius-32 top corners from `AppTheme.bottomSheetTheme`). This is its
/// second real use (spec-003 selection/unlock sheets), per plan.
///
/// Selection/unlock screens use this instead of `showDialog`: they live
/// outside the vault shell and do not go through `VaultShellRouter`.
class KvBottomSheet {
  KvBottomSheet._();

  /// `barrierAlpha` follows the PIXEL_SPEC bottom-sheet backdrop table:
  /// 0.42 default, 0.30 for confirmations, 0.22 for a saving overlay.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    double barrierAlpha = 0.42,
    bool isDismissible = true,
    bool enableDrag = true,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      barrierColor: Colors.black.withValues(alpha: barrierAlpha),
      constraints: width < Breakpoints.mobile
          ? null
          : const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) => SafeArea(child: builder(sheetContext)),
    );
  }
}
