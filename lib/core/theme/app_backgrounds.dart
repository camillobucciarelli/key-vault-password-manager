import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppBackgrounds {
  AppBackgrounds._();

  static LinearGradient gradient(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LinearGradient(
      begin: const Alignment(-1.0, -0.92),
      end: const Alignment(0.92, 1.0),
      colors: isDark
          ? [
              const Color(0xFF11091F),
              AppColors.primaryDark.withValues(alpha: 0.84),
              AppColors.tertiaryDark.withValues(alpha: 0.52),
              const Color(0xFF1A0F2D),
            ]
          : [
              const Color(0xFFF8F3FF),
              colorScheme.primary.withValues(alpha: 0.2),
              AppColors.secondaryLight.withValues(alpha: 0.22),
              const Color(0xFFF2EAFF),
            ],
      stops: const [0.0, 0.34, 0.74, 1.0],
    );
  }
}
