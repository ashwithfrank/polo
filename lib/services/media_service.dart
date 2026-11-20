import 'package:flutter/services.dart';

/// Compresses video and converts to M4A (AAC) with the phone's own codecs.
class MediaService {
  MediaService._();

  static const _channel = MethodChannel('com.aos.polo/media');

  static void Function(int percent)? _onProgress;

  /// Converts [input] into [output]. With [audioOnly] the picture is dropped
  /// and the result is AAC audio. [height] shrinks the video to that height
  /// (keeping the shape), and [videoKbps] sets how much data each second may use.
  static Future<void> convert({
    required String input,
    required String output,
    bool audioOnly = false,
    int? height,
    int? videoKbps,
    void Function(int percent)? onProgress,
  }) async {
    _onProgress = onProgress;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'progress') {
        final v = call.arguments;
        if (v is num) _onProgress?.call(v.round().clamp(0, 100));
      }
    });
    try {
      await _channel.invokeMethod<void>('convert', {
        'input': input,
        'output': output,
        'audio': audioOnly,
        'height': height ?? 0,
        'videoKbps': videoKbps ?? 0,
      });
    } on PlatformException catch (e) {
      if (e.code == 'cancelled') throw const MediaCancelled();
      if (e.code == 'noaudio') throw const FormatException('This file has no sound to save');
      throw FormatException(
        e.code == 'busy'
            ? 'Another conversion is running'
            : "Couldn't convert this file\n${e.message ?? ''}",
      );
    } on MissingPluginException {
      throw const FormatException('Conversion needs the latest Polo build');
    } finally {
      _onProgress = null;
    }
  }

  static Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } catch (_) {}
  }
}

class MediaCancelled implements Exception {
  const MediaCancelled();
}