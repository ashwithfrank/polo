import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

class ThemeController extends ChangeNotifier {
  static const _modeKey = 'theme_mode';
  static const _accentKey = 'theme_accent';
  static const _oledKey = 'theme_oled';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Color _accent = PoloColors.orange;
  Color get accent => _accent;

  bool _oled = false;

  /// Pure black background in the dark theme.
  bool get oled => _oled;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_modeKey);
    _mode = ThemeMode.values.firstWhere(
          (m) => m.name == saved,
      orElse: () => ThemeMode.system,
    );
    final accent = prefs.getInt(_accentKey);
    if (accent != null) _accent = Color(accent);
    _oled = prefs.getBool(_oledKey) ?? false;
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
  }

  Future<void> setAccent(Color color) async {
    if (color.toARGB32() == _accent.toARGB32()) return;
    _accent = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_accentKey, color.toARGB32());
  }

  Future<void> setOled(bool value) async {
    if (value == _oled) return;
    _oled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_oledKey, value);
  }
}