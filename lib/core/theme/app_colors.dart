import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Core palette
  static const Color primary = Color(0xFF818CF8);
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color primaryDark = Color(0xFF4C1D95);

  // Companion palette
  static const Color secondary = Color(0xFF6366F1);
  static const Color secondaryLight = Color(0xFFA78BFA);
  static const Color secondaryDark = Color(0xFF5B21B6);

  static const Color tertiary = Color(0xFF4F46E5);
  static const Color tertiaryLight = Color(0xFFC084FC);
  static const Color tertiaryDark = Color(0xFF6B21A8);

  static const Color darkSeed = Color(0xFF818CF8);

  // Neutral Colors - Light Mode (tints of #020617 -> #0F172A)
  static const Color backgroundLight = Color(0xFFEFF3FB);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF334155);
  static const Color dividerLight = Color(0xFFC9D3E4);

  // Gradient helpers
  static const Color darkGradientFrom = Color(0xFF020617);
  static const Color darkGradientTo = Color(0xFF0F172A);
  static const Color lightGradientFrom = Color(0xFFF0F2F8); // from #020617
  static const Color lightGradientTo = Color(0xFFE6EBF7); // from #0F172A

  // Neutral Colors - Dark Mode
  static const Color backgroundDark = Color(0xFF020617);
  static const Color surfaceDark = Color(0xFF0F172A);
  static const Color textPrimaryDark = Color(0xFFE2E8F0);
  static const Color textSecondaryDark = Color(0xFF94A3B8);
  static const Color dividerDark = Color(0xFF1E293B);

  // Semantic Colors
  static const Color error = Color(0xFFD1435B);
  static const Color success = Color(0xFF2F9E72);
  static const Color warning = Color(0xFFC9832A);
}
