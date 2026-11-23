import 'package:flutter/services.dart';

/// Password-protected ZIP files (AES-256), made and opened with Android code.
class ZipToolService {
  ZipToolService._();

  static const _channel = MethodChannel('com.aos.polo/ziptool');

  static Future<bool> isEncrypted(String input) async {
    final v = await _call<bool>('isEncrypted', {'input': input});
    return v ?? false;
  }

  static Future<void> create(List<String> paths, String output, String password) =>
      _call<int>('create', {'paths': paths, 'output': output, 'password': password});

  /// Returns how many items were extracted.
  static Future<int> extract(String input, String dest, String password) async {
    final v = await _call<int>('extract', {'input': input, 'dest': dest, 'password': password});
    return v ?? 0;
  }

  static Future<T?> _call<T>(String method, Map<String, Object> args) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw FormatException(
        e.code == 'wrong_password' ? 'That password is not right' : "Couldn't work with this ZIP",
      );
    } on MissingPluginException {
      throw const FormatException('This needs the latest Polo build');
    }
  }
}
