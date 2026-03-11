import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppBackgrounds {
  AppBackgrounds._();

  static LinearGradient gradient(BuildContext context) {
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
              const Color(0xFFFFF8EC),
              const Color(0xFFFFE5CC),
              const Color(0xFFDDF3EC),
              const Color(0xFFE9F1FF),
            ],
      stops: const [0.0, 0.34, 0.74, 1.0],
    );
  }
}
