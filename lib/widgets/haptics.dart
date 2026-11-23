import 'package:flutter/services.dart';

import '../services/settings_controller.dart';

/// Small vibrations, switched and scaled by the Vibration settings.
///
/// Polo asks the phone's vibration motor directly, because the system's
/// "touch feedback" is often switched off or too faint to feel.
class Haptics {
  Haptics._();

  static const _channel = MethodChannel('com.aos.polo/haptic');

  static bool get _on => SettingsController.current?.haptics ?? true;
  static int get _level => SettingsController.current?.hapticStrength ?? 2;

  static void _buzz(int ms, int amp, void Function() fallback) {
    // Level 1 is light, 2 is medium, 3 is strong.
    final scale = _level;
    _channel
        .invokeMethod<void>('buzz', {
          'ms': ms * scale,
          'amp': (amp * (0.6 + 0.2 * scale)).round().clamp(1, 255),
        })
        .catchError((Object _) => fallback());
  }

  static void select() {
    if (_on) _buzz(10, 110, HapticFeedback.selectionClick);
  }

  static void tap() {
    if (_on) _buzz(14, 150, HapticFeedback.lightImpact);
  }

  static void strong() {
    if (_on) _buzz(24, 220, HapticFeedback.mediumImpact);
  }

  /// Used by Settings so the person can feel the strength they picked.
  static void test() => strong();
}
