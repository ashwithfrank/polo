import 'dart:io';

import 'package:flutter/services.dart';

import 'file_service.dart';
import 'settings_controller.dart';

/// Where a tool puts what it makes.
enum OutputMode {
  /// Edits go next to the original; things made from scratch go to Polo.
  smart,

  /// Always next to the original file.
  nextToOriginal,

  /// Always in the Polo folder.
  poloFolder,
}

enum OutputKind {
  images('Images'),
  documents('Documents'),
  scans('Scans'),
  qr('QR codes'),
  archives('Archives'),
  media('Media'),
  other('Other');

  const OutputKind(this.folder);
  final String folder;
}

class OutputLocation {
  OutputLocation._();

  static const _channel = MethodChannel('cos.aos.polo/storage');

  /// Tells Android about a new file so Gallery and other apps show it.
  static Future<void> announce(String path) async {
    try {
      await _channel.invokeMethod<void>('scanFile', {'path': path});
    } catch (_) {}
  }

  static String get poloRoot => '${FileService.rootPath}/Polo';

  /// The folder to save into. [sourceDir] is where the original lives.
  /// [fromScratch] is true for things with no original (scans, QR codes).
  static Future<String> resolve(
    String sourceDir,
    OutputKind kind, {
    bool fromScratch = false,
  }) async {
    final mode = SettingsController.current?.outputMode ?? OutputMode.smart;
    final toPolo = switch (mode) {
      OutputMode.smart => fromScratch,
      OutputMode.nextToOriginal => false,
      OutputMode.poloFolder => true,
    };
    // A scratch result has no sensible "next to" folder, so it always has a home.
    if (!toPolo && !(fromScratch && mode == OutputMode.nextToOriginal)) {
      return sourceDir;
    }
    if (sourceDir == '$poloRoot/${kind.folder}') return sourceDir;
    final dir = '$poloRoot/${kind.folder}';
    await Directory(dir).create(recursive: true);
    return dir;
  }

  /// A short "Saved ..." line for tool screens, e.g. hint('the first PDF', documents).
  static String hint(String original, OutputKind kind) {
    final mode = SettingsController.current?.outputMode ?? OutputMode.smart;
    return mode == OutputMode.poloFolder
        ? 'Saved in Polo/${kind.folder}'
        : 'Saved next to $original';
  }
}
