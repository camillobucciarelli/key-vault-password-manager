import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
// Note: We'll need to add google_fonts to pubspec.yaml

import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surfaceLight,
        error: AppColors.error,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.textPrimaryLight,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: AppColors.backgroundLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimaryLight,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceLight,
        constraints: const BoxConstraints(minHeight: 56),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.dividerLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.dividerLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondaryLight),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.dividerLight, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.dividerLight,
        thickness: 1,
        space: 1,
      ),
      // Apply Google Fonts - Poppins
      textTheme: GoogleFonts.poppinsTextTheme(ThemeData.light().textTheme)
          .copyWith(
            displayLarge: GoogleFonts.poppins(
              color: AppColors.textPrimaryLight,
            ),
            displayMedium: GoogleFonts.poppins(
              color: AppColors.textPrimaryLight,
            ),
            displaySmall: GoogleFonts.poppins(
              color: AppColors.textPrimaryLight,
            ),
            headlineLarge: GoogleFonts.poppins(
              color: AppColors.textPrimaryLight,
            ),
            headlineMedium: GoogleFonts.poppins(
              color: AppColors.textPrimaryLight,
            ),
            headlineSmall: GoogleFonts.poppins(
              color: AppColors.textPrimaryLight,
            ),
            titleLarge: GoogleFonts.poppins(color: AppColors.textPrimaryLight),
            titleMedium: GoogleFonts.poppins(color: AppColors.textPrimaryLight),
            titleSmall: GoogleFonts.poppins(color: AppColors.textPrimaryLight),
            bodyLarge: GoogleFonts.poppins(color: AppColors.textPrimaryLight),
            bodyMedium: GoogleFonts.poppins(color: AppColors.textPrimaryLight),
            bodySmall: GoogleFonts.poppins(color: AppColors.textSecondaryLight),
            labelLarge: GoogleFonts.poppins(color: AppColors.textPrimaryLight),
            labelMedium: GoogleFonts.poppins(color: AppColors.textPrimaryLight),
            labelSmall: GoogleFonts.poppins(
              color: AppColors.textSecondaryLight,
            ),
          ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary:
            AppColors.primaryLight, // Slightly lighter primary for dark mode
        secondary: AppColors.secondaryLight,
        surface: AppColors.surfaceDark,
        error: AppColors.error,
        onPrimary: Colors.white,
        onSecondary: Colors.black,
        onSurface: AppColors.textPrimaryDark,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: AppColors.backgroundDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimaryDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryLight,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceDark,
        constraints: const BoxConstraints(minHeight: 56),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.dividerDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.dividerDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryLight, width: 2),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondaryDark),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.dividerDark, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.dividerDark,
        thickness: 1,
        space: 1,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme)
          .copyWith(
            displayLarge: GoogleFonts.poppins(color: AppColors.textPrimaryDark),
            displayMedium: GoogleFonts.poppins(
              color: AppColors.textPrimaryDark,
            ),
            displaySmall: GoogleFonts.poppins(color: AppColors.textPrimaryDark),
            headlineLarge: GoogleFonts.poppins(
              color: AppColors.textPrimaryDark,
            ),
            headlineMedium: GoogleFonts.poppins(
              color: AppColors.textPrimaryDark,
            ),
            headlineSmall: GoogleFonts.poppins(
              color: AppColors.textPrimaryDark,
            ),
            titleLarge: GoogleFonts.poppins(color: AppColors.textPrimaryDark),
            titleMedium: GoogleFonts.poppins(color: AppColors.textPrimaryDark),
            titleSmall: GoogleFonts.poppins(color: AppColors.textPrimaryDark),
            bodyLarge: GoogleFonts.poppins(color: AppColors.textPrimaryDark),
            bodyMedium: GoogleFonts.poppins(color: AppColors.textPrimaryDark),
            bodySmall: GoogleFonts.poppins(color: AppColors.textSecondaryDark),
            labelLarge: GoogleFonts.poppins(color: AppColors.textPrimaryDark),
            labelMedium: GoogleFonts.poppins(color: AppColors.textPrimaryDark),
            labelSmall: GoogleFonts.poppins(color: AppColors.textSecondaryDark),
          ),
    );
  }
}
