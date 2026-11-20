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

/// The accent colours Polo offers. The first is the original look.
class AccentPreset {
  const AccentPreset(this.name, this.color);

  final String name;
  final Color color;

  static const presets = [
    AccentPreset('Orange', PoloColors.orange),
    AccentPreset('Blue', Color(0xFF2F6FED)),
    AccentPreset('Green', Color(0xFF2E9E5B)),
    AccentPreset('Purple', Color(0xFF8A55E0)),
    AccentPreset('Red', Color(0xFFE0423A)),
    AccentPreset('Pink', Color(0xFFE0508F)),
    AccentPreset('Yellow', Color(0xFFE0A800)),
  ];
}

class AppTheme {
  /// Light theme with a tinted background and buttons in [accent].
  static ThemeData light([Color accent = PoloColors.orange]) {
    if (_isOrange(accent)) {
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

    final hsl = HSLColor.fromColor(accent);
    Color tint(double saturation, double lightness) =>
        HSLColor.fromAHSL(1, hsl.hue, saturation, lightness).toColor();

    // Keep the button colour dark enough to read on a light page.
    final primary = hsl.lightness > 0.5 ? hsl.withLightness(0.5).toColor() : accent;
    final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.light).copyWith(
      primary: primary,
      onPrimary: _onColor(primary),
      primaryContainer: tint(0.85, 0.83),
      onPrimaryContainer: tint(0.5, 0.14),
      surface: tint(0.9, 0.96),
      onSurface: tint(0.45, 0.13),
      surfaceContainerHighest: tint(0.8, 0.91),
    );
    return _build(scheme);
  }

  /// Dark theme. With [oled] the background is pure black.
  static ThemeData dark([Color accent = PoloColors.orange, bool oled = false]) {
    final ColorScheme base;
    if (_isOrange(accent)) {
      base = ColorScheme.fromSeed(
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
    } else {
      final hsl = HSLColor.fromColor(accent);
      Color tint(double saturation, double lightness) =>
          HSLColor.fromAHSL(1, hsl.hue, saturation, lightness).toColor();

      // Lighten the button colour so it stands out on a dark page.
      final primary = hsl.lightness < 0.62 ? hsl.withLightness(0.68).toColor() : accent;
      base = ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark).copyWith(
        primary: primary,
        onPrimary: tint(0.3, 0.08),
        primaryContainer: tint(0.5, 0.22),
        onPrimaryContainer: tint(0.4, 0.9),
        surface: tint(0.25, 0.08),
        onSurface: tint(0.25, 0.9),
        surfaceContainerHighest: tint(0.25, 0.14),
      );
    }

    if (!oled) return _build(base);

    // True black saves battery on OLED screens. Cards stay a hair lighter so
    // they can still be told apart.
    final hsl = HSLColor.fromColor(base.surfaceContainerHighest);
    return _build(
      base.copyWith(
        surface: Colors.black,
        surfaceContainerHighest: hsl.withLightness(0.1).toColor(),
      ),
    );
  }

  static bool _isOrange(Color c) => c.toARGB32() == PoloColors.orange.toARGB32();

  static Color _onColor(Color c) =>
      ThemeData.estimateBrightnessForColor(c) == Brightness.dark ? Colors.white : Colors.black;

  static ThemeData _build(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
        },
      ),
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
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerHighest,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
