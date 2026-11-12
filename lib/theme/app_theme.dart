import 'package:flutter/material.dart';

/// Single source of truth for Resonant's colours. Do not use raw colour
/// literals elsewhere; add a named entry here instead.
abstract final class AppColors {
  static const background = Color(0xFF202124);
  static const surface = Color(0xFF303134);
  static const outline = Color(0xFF5F6368);
  static const keyboardBackdrop = Color(0xFF080A1B);

  static const primary = Color(0xFF2468D9);
  static const accent = Color(0xFF8AB4F8);
  static const primaryTint = Color(0xFFB8D1FF);

  static const textPrimary = Color(0xFFE8EAED);
  static const textMuted = Color(0xFF9AA0A6);

  static const success = Color(0xFF9FE0B5);
  static const warning = Color(0xFFFFD18A);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.accent,
    onPrimary: AppColors.background,
    secondary: AppColors.primary,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    outline: AppColors.outline,
    error: const Color(0xFFF28B82),
  );
  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    visualDensity: VisualDensity.standard,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: shape,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.outline,
      thickness: 1,
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 48),
        shape: shape,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 48),
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.accent,
        side: const BorderSide(color: AppColors.outline),
        minimumSize: const Size(64, 48),
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accent,
        minimumSize: const Size(48, 48),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surface,
      contentTextStyle: TextStyle(color: AppColors.textPrimary),
      shape: shape,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: shape,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: AppColors.outline),
      ),
    ),
    textTheme: ThemeData(brightness: Brightness.dark).textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
  );
}
