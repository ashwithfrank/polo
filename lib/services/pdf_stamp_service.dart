import 'package:flutter/services.dart';

/// Draws a watermark or page numbers on a PDF with PdfBox. Nothing is uploaded.
class PdfStampService {
  PdfStampService._();

  static const _channel = MethodChannel('com.aos.polo/pdflock');

  static Future<void> watermark({
    required String input,
    required String output,
    required String text,
    required double size,
    required double opacity,
    required double angle,
  }) =>
      _run('watermark', {
        'input': input,
        'output': output,
        'text': text,
        'size': size,
        'opacity': opacity,
        'angle': angle,
      });

  /// [position] is 0 to 5: bottom left, center, right, then top left, center, right.
  static Future<void> pageNumbers({
    required String input,
    required String output,
    required String format,
    required int position,
    required double size,
    required int start,
  }) =>
      _run('pageNumbers', {
        'input': input,
        'output': output,
        'format': format,
        'position': position,
        'size': size,
        'start': start,
      });

  static Future<void> _run(String method, Map<String, Object> args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on PlatformException catch (e) {
      throw FormatException(switch (e.code) {
        'wrong_password' => 'This PDF has a password. Unlock it first with Lock or unlock PDF',
        'bad_text' => "Some characters can't be used. Stick to English letters, numbers and symbols",
        _ => "Couldn't change this PDF",
      });
    } on MissingPluginException {
      throw const FormatException('This needs the latest Polo build');
    }
  }
}
