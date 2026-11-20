import 'package:flutter/services.dart';

import '../services/settings_controller.dart';

/// Small vibrations, switched by the "Vibration" setting.
class Haptics {
  Haptics._();

  static bool get _on => SettingsController.current?.haptics ?? true;

  static void select() {
    if (_on) HapticFeedback.selectionClick();
  }

  static void tap() {
    if (_on) HapticFeedback.lightImpact();
  }

  static void strong() {
    if (_on) HapticFeedback.mediumImpact();
  }
}
