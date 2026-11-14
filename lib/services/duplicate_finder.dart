import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import '../models/file_item.dart';
import 'file_service.dart';

/// Files with identical content. [files] has at least two entries, oldest first.
class DuplicateGroup {
  const DuplicateGroup(this.files);

  final List<FileItem> files;

  int get size => files.first.size;

  /// Space freed by keeping just one copy.
  int get wastedBytes => size * (files.length - 1);
}

class DuplicateFinder {
  /// Smaller files are ignored; they're rarely worth cleaning up.
  static const minSize = 10 * 1024;

  /// Scans internal storage in a background isolate. Biggest savings first.
  static Future<List<DuplicateGroup>> scan() async {
    final raw = await Isolate.run(_scanSync);
    final groups = [
      for (final g in raw)
        DuplicateGroup([
          for (final (path, size, ms) in g)
            FileItem(
              path: path,
              name: path.split('/').last,
              isDirectory: false,
              size: size,
              modified: DateTime.fromMillisecondsSinceEpoch(ms),
            ),
        ]),
    ];
    groups.sort((a, b) => b.wastedBytes.compareTo(a.wastedBytes));
    return groups;
  }
}

typedef _Row = (String, int, int);

List<List<_Row>> _scanSync() {
  const root = FileService.rootPath;
  const skipped = {'$root/Android/data', '$root/Android/obb'};

  // 1. Group every file by size. Only same-size files can be identical.
  final bySize = <int, List<_Row>>{};
  final stack = <String>[root];
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    List<FileSystemEntity> entries;
    try {
      entries = Directory(dir).listSync(followLinks: false);
    } catch (_) {
      continue;
    }
    for (final e in entries) {
      final name = e.path.split('/').last;
      if (name.startsWith('.')) continue;
      if (e is Directory) {
        if (!skipped.contains(e.path)) stack.add(e.path);
      } else if (e is File) {
        try {
          final stat = e.statSync();
          if (stat.size >= DuplicateFinder.minSize) {
            (bySize[stat.size] ??= []).add(
              (e.path, stat.size, stat.modified.millisecondsSinceEpoch),
            );
          }
        } catch (_) {}
      }
    }
  }

  // 2. Same size: compare the first 64 KB, then the whole file.
  final result = <List<_Row>>[];
  for (final sameSize in bySize.values) {
    if (sameSize.length < 2) continue;

    final byPartial = <String, List<_Row>>{};
    for (final row in sameSize) {
      final h = _hash(row.$1, limit: 64 * 1024);
      if (h != null) (byPartial[h] ??= []).add(row);
    }
    for (final candidates in byPartial.values) {
      if (candidates.length < 2) continue;
      final byFull = <String, List<_Row>>{};
      for (final row in candidates) {
        final h = _hash(row.$1);
        if (h != null) (byFull[h] ??= []).add(row);
      }
      for (final group in byFull.values) {
        if (group.length < 2) continue;
        group.sort((a, b) => a.$3.compareTo(b.$3));
        result.add(group);
      }
    }
  }
  return result;
}

/// MD5 of a file, or of its first [limit] bytes. Null if it can't be read.
String? _hash(String path, {int? limit}) {
  try {
    final output = _DigestCapture();
    final input = md5.startChunkedConversion(output);
    final raf = File(path).openSync();
    try {
      var remaining = limit ?? raf.lengthSync();
      while (remaining > 0) {
        final chunk = raf.readSync(remaining < 65536 ? remaining : 65536);
        if (chunk.isEmpty) break;
        input.add(chunk);
        remaining -= chunk.length;
      }
    } finally {
      raf.closeSync();
    }
    input.close();
    return output.value?.toString();
  } catch (_) {
    return null;
  }
}

class _DigestCapture implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}