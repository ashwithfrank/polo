import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Facts about a file's contents, used by the inspector and compare screens.
/// Heavy work runs in isolates and only passes plain values back.
class InspectService {
  InspectService._();

  /// Width and height of a picture, without decoding all of it.
  static Future<(int, int)?> imageSize(String path) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromFilePath(path);
      try {
        final d = await ui.ImageDescriptor.encoded(buffer);
        final size = (d.width, d.height);
        d.dispose();
        return size;
      } finally {
        buffer.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  /// Width and height of an encoded picture held in memory.
  static Future<(int, int)?> imageSizeOfBytes(Uint8List bytes) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      try {
        final d = await ui.ImageDescriptor.encoded(buffer);
        final size = (d.width, d.height);
        d.dispose();
        return size;
      } finally {
        buffer.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  /// Lines, words and characters of a text file. Null for big or binary files.
  static Future<TextStats?> textStats(String path) {
    return Isolate.run(() async {
      final file = File(path);
      if (await file.length() > 5 * 1024 * 1024) return null;
      final bytes = await file.readAsBytes();
      if (bytes.contains(0)) return null;
      var valid = true;
      String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        valid = false;
        text = latin1.decode(bytes);
      }
      final crlf = text.contains('\r\n');
      final lines = text.isEmpty ? 0 : '\n'.allMatches(text).length + (text.endsWith('\n') ? 0 : 1);
      final words = RegExp(r'\S+').allMatches(text).length;
      return TextStats(
        lines: lines,
        words: words,
        characters: text.length,
        utf8: valid,
        windowsLineEndings: crlf,
      );
    });
  }

  /// What is inside a folder, all the way down.
  static Future<FolderStats> folderStats(String path) {
    return Isolate.run(() {
      var files = 0, folders = 0, bytes = 0;
      try {
        for (final e in Directory(path).listSync(recursive: true, followLinks: false)) {
          if (e is File) {
            files++;
            try {
              bytes += e.lengthSync();
            } catch (_) {}
          } else if (e is Directory) {
            folders++;
          }
        }
      } catch (_) {}
      return FolderStats(files: files, folders: folders, bytes: bytes);
    });
  }

  /// True if both files hold exactly the same bytes.
  static Future<bool> sameBytes(String a, String b) {
    return Isolate.run(() async {
      final fa = File(a), fb = File(b);
      if (await fa.length() != await fb.length()) return false;
      final ra = await fa.open();
      final rb = await fb.open();
      try {
        const chunk = 256 * 1024;
        while (true) {
          final x = await ra.read(chunk);
          if (x.isEmpty) return true;
          final y = await rb.read(chunk);
          if (!_equal(x, y)) return false;
        }
      } finally {
        await ra.close();
        await rb.close();
      }
    });
  }

  /// A line by line summary of how two text files differ. Null when a file
  /// is too big, is not text, or differs too much to summarise.
  static Future<TextDiff?> textDiff(String a, String b) {
    return Isolate.run(() async {
      final fa = File(a), fb = File(b);
      if (await fa.length() > 1024 * 1024 || await fb.length() > 1024 * 1024) return null;
      final ba = await fa.readAsBytes();
      final bb = await fb.readAsBytes();
      if (ba.contains(0) || bb.contains(0)) return null;
      final left = const LineSplitter().convert(utf8.decode(ba, allowMalformed: true));
      final right = const LineSplitter().convert(utf8.decode(bb, allowMalformed: true));

      // Lines that match at the start and the end need no work.
      var start = 0;
      while (start < left.length && start < right.length && left[start] == right[start]) {
        start++;
      }
      var endL = left.length, endR = right.length;
      while (endL > start && endR > start && left[endL - 1] == right[endR - 1]) {
        endL--;
        endR--;
      }
      final n = endL - start, m = endR - start;
      if (n * m > 4000000) return null;

      // Longest common subsequence of the lines in the middle.
      final w = m + 1;
      final table = Uint16List((n + 1) * w);
      for (var i = n - 1; i >= 0; i--) {
        for (var j = m - 1; j >= 0; j--) {
          table[i * w + j] = left[start + i] == right[start + j]
              ? table[(i + 1) * w + j + 1] + 1
              : (table[(i + 1) * w + j] >= table[i * w + j + 1]
              ? table[(i + 1) * w + j]
              : table[i * w + j + 1]);
        }
      }

      final lines = <DiffLine>[];
      var added = 0, removed = 0;
      var i = 0, j = 0;
      void put(bool add, int number, String text) {
        if (add) {
          added++;
        } else {
          removed++;
        }
        if (lines.length < 300) lines.add(DiffLine(add: add, number: number, text: text));
      }

      while (i < n || j < m) {
        if (i < n && j < m && left[start + i] == right[start + j]) {
          i++;
          j++;
        } else if (j < m && (i == n || table[i * w + j + 1] >= table[(i + 1) * w + j])) {
          put(true, start + j + 1, right[start + j]);
          j++;
        } else {
          put(false, start + i + 1, left[start + i]);
          i++;
        }
      }
      return TextDiff(lines: lines, added: added, removed: removed);
    });
  }
}

bool _equal(Uint8List x, Uint8List y) {
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}

class TextStats {
  const TextStats({
    required this.lines,
    required this.words,
    required this.characters,
    required this.utf8,
    required this.windowsLineEndings,
  });

  final int lines;
  final int words;
  final int characters;
  final bool utf8;
  final bool windowsLineEndings;
}

class FolderStats {
  const FolderStats({required this.files, required this.folders, required this.bytes});

  final int files;
  final int folders;
  final int bytes;
}

class DiffLine {
  const DiffLine({required this.add, required this.number, required this.text});

  /// True for a line only in the second file, false for one only in the first.
  final bool add;
  final int number;
  final String text;
}

class TextDiff {
  const TextDiff({required this.lines, required this.added, required this.removed});

  /// The first few changes. See [added] and [removed] for the full totals.
  final List<DiffLine> lines;
  final int added;
  final int removed;
}