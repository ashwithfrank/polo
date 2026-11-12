import 'package:flutter/material.dart';

class PoloColors {
  static const orange = Color(0xFFF27A1A);

  // Light (cream)
  static const creamBg = Color(0xFFFFF6E9);
  static const creamSurface = Color(0xFFFFEBD2);
  static const creamContainer = Color(0xFFFFD9AE);
  static const brownText = Color(0xFF3B2410);

  // Dark (warm charcoal)
  static const darkBg = Color(0xFF1C1612);
  static const darkSurface = Color(0xFF2A211A);
  static const darkContainer = Color(0xFF5A2E0E);
  static const softOrange = Color(0xFFFF9A4D);
  static const darkText = Color(0xFFF5E6D3);
}

class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: PoloColors.orange,
      brightness: Brightness.light,
    ).copyWith(
      primary: PoloColors.orange,
      onPrimary: PoloColors.creamBg,
      primaryContainer: PoloColors.creamContainer,
      onPrimaryContainer: PoloColors.brownText,
      surface: PoloColors.creamBg,
      onSurface: PoloColors.brownText,
      surfaceContainerHighest: PoloColors.creamSurface,
    );
    return _build(scheme);
  }

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: PoloColors.orange,
      brightness: Brightness.dark,
    ).copyWith(
      primary: PoloColors.softOrange,
      onPrimary: PoloColors.darkBg,
      primaryContainer: PoloColors.darkContainer,
      onPrimaryContainer: PoloColors.darkText,
      surface: PoloColors.darkBg,
      onSurface: PoloColors.darkText,
      surfaceContainerHighest: PoloColors.darkSurface,
    );
    return _build(scheme);
  }

  static ThemeData _build(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        indicatorColor: scheme.primaryContainer,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerHighest,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}