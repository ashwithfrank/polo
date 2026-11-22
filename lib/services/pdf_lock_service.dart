import 'package:flutter/services.dart';

/// Adds or removes a PDF password with Android's own tools. Nothing is uploaded.
class PdfLockService {
  PdfLockService._();

  static const _channel = MethodChannel('com.aos.polo/pdflock');

  static Future<bool> isLocked(String input) async {
    try {
      return await _channel.invokeMethod<bool>('isLocked', {'input': input}) ?? false;
    } on PlatformException {
      throw const FormatException("Couldn't open this PDF");
    } on MissingPluginException {
      throw const FormatException('This needs the latest Polo build');
    }
  }

  static Future<void> lock(String input, String output, String password) =>
      _run('lock', input, output, password);

  static Future<void> unlock(String input, String output, String password) =>
      _run('unlock', input, output, password);

  static Future<void> _run(String method, String input, String output, String password) async {
    try {
      await _channel.invokeMethod<void>(method, {
        'input': input,
        'output': output,
        'password': password,
      });
    } on PlatformException catch (e) {
      throw FormatException(
        e.code == 'wrong_password' ? 'That password is not right' : "Couldn't change this PDF",
      );
    } on MissingPluginException {
      throw const FormatException('This needs the latest Polo build');
    }
  }
}
