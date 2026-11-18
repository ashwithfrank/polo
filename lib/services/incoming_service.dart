import 'dart:io';

import 'package:flutter/services.dart';

import '../models/file_item.dart';

/// A file another app asked Polo to open or receive. Not read yet.
class IncomingFile {
  const IncomingFile({required this.uri, required this.name, this.size});

  final String uri;
  final String name;
  final int? size;
}

class IncomingIntent {
  const IncomingIntent({
    required this.isView,
    required this.files,
    this.isPick = false,
    this.multiple = false,
    this.mimeTypes = const [],
  });

  /// True for "Open with", false for "Share".
  final bool isView;
  final List<IncomingFile> files;

  /// True when another app wants the user to pick files in Polo (for example an
  /// upload button in a browser).
  final bool isPick;

  /// For a pick: whether several files may be chosen, and what kinds are wanted.
  final bool multiple;
  final List<String> mimeTypes;
}

/// Files that arrive from "Open with" and "Share" in other apps.
class IncomingService {
  IncomingService._();

  static const _channel = MethodChannel('com.aos.polo/intent');

  static IncomingIntent? _parse(Object? raw) {
    if (raw is! Map) return null;
    final files = raw['files'];
    if (files is! List) return null;
    return IncomingIntent(
      isView: raw['action'] == 'view',
      isPick: raw['action'] == 'pick',
      multiple: raw['multiple'] == true,
      mimeTypes: [
        for (final t in (raw['mimeTypes'] as List?) ?? const []) t.toString(),
      ],
      files: [
        for (final f in files.whereType<Map>())
          IncomingFile(
            uri: f['uri'] as String,
            name: f['name'] as String,
            size: (f['size'] as num?)?.toInt(),
          ),
      ],
    );
  }

  /// What Polo was started with, if anything.
  static Future<IncomingIntent?> initial() async {
    try {
      return _parse(await _channel.invokeMethod<Object>('getInitial'));
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Called when Polo is already open and gets another file.
  static void listen(void Function(IncomingIntent intent) onIntent) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'newIntent') {
        final parsed = _parse(call.arguments);
        if (parsed != null) onIntent(parsed);
      }
    });
  }

  /// Gives the chosen files back to the app that asked and closes Polo's picker.
  static Future<void> finishPick(List<String> paths) =>
      _channel.invokeMethod<void>('finishPick', {'paths': paths});

  /// Tells the app that asked that nothing was chosen.
  static Future<void> cancelPick() => _channel.invokeMethod<void>('cancelPick');

  static const _mimeByExtension = {
    'pdf': 'application/pdf',
    'zip': 'application/zip',
    'apk': 'application/vnd.android.package-archive',
    'json': 'application/json',
    'xml': 'application/xml',
    'txt': 'text/plain',
    'csv': 'text/csv',
    'md': 'text/markdown',
    'html': 'text/html',
    'htm': 'text/html',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'rar': 'application/vnd.rar',
    '7z': 'application/x-7z-compressed',
    'gz': 'application/gzip',
    'tar': 'application/x-tar',
  };

  static String _mimeOf(FileItem item) {
    final ext = item.extension == 'jpg' ? 'jpeg' : item.extension;
    return switch (item.kind) {
      FileKind.image => 'image/$ext',
      FileKind.video => 'video/$ext',
      FileKind.audio => 'audio/$ext',
      _ => _mimeByExtension[item.extension] ?? 'application/octet-stream',
    };
  }

  /// Whether [item] is one of the kinds an app asked for ("image/*",
  /// "application/pdf", "*/*" and so on).
  static bool matchesMime(FileItem item, List<String> wanted) {
    if (wanted.isEmpty) return true;
    final mime = _mimeOf(item);
    for (final w in wanted) {
      if (w == '*/*' || w == '*' || w == mime) return true;
      if (w.endsWith('/*') && mime.startsWith(w.substring(0, w.length - 1))) return true;
    }
    return false;
  }

  static void stopListening() => _channel.setMethodCallHandler(null);

  /// Gets a real file for each item, copying into the cache only when Android
  /// doesn't give a path. Throws a [FormatException] with a readable message.
  static Future<List<FileItem>> resolveAll(List<IncomingFile> files) async {
    final items = <FileItem>[];
    for (final f in files) {
      try {
        final map = await _channel.invokeMapMethod<String, Object?>(
          'resolve',
          {'uri': f.uri},
        );
        final path = map?['path'] as String?;
        if (path == null) throw const FormatException("Couldn't open this file");
        final stat = await File(path).stat();
        items.add(
          FileItem(
            path: path,
            name: (map?['name'] as String?) ?? path.split('/').last,
            isDirectory: false,
            size: stat.size,
            modified: stat.modified,
          ),
        );
      } on PlatformException catch (e) {
        throw FormatException(e.message ?? "Couldn't open this file");
      }
    }
    return items;
  }
}