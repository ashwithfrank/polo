import 'package:flutter/services.dart';

/// Total and free space on internal storage, read natively from Android.
class StorageInfo {
  const StorageInfo({required this.total, required this.free});

  final int total;
  final int free;

  int get used => total - free;
  double get usedFraction => total == 0 ? 0 : (used / total).clamp(0.0, 1.0);

  static const _channel = MethodChannel('cos.aos.polo/storage');

  /// Returns null if the numbers can't be read.
  static Future<StorageInfo?> read() async {
    try {
      final map = await _channel.invokeMapMethod<String, int>('getStorageInfo');
      final total = map?['total'];
      final free = map?['free'];
      if (total == null || free == null) return null;
      return StorageInfo(total: total, free: free);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}