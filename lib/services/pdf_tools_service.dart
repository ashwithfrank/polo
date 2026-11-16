import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

import 'file_service.dart';

/// Merging, splitting, rotating and converting PDFs. Everything stays on the
/// device. The PDF engine is the same one the PDF viewer uses.
class PdfToolsService {
  PdfToolsService(this._files);

  final FileService _files;

  static bool _ready = false;

  static void _init() {
    if (_ready) return;
    pdfrxFlutterInitialize();
    _ready = true;
  }

  /// Opens a PDF for editing. Throws a [FormatException] with a readable
  /// message if it can't be opened.
  static Future<PdfDocument> open(String path) async {
    _init();
    try {
      return await PdfDocument.openFile(path);
    } on PdfPasswordException {
      throw FormatException(
        '${path.split('/').last} is password-protected. Polo can\'t edit protected PDFs yet',
      );
    } catch (_) {
      throw FormatException("Couldn't open ${path.split('/').last}");
    }
  }

  Future<int> pageCount(String path) async {
    final doc = await open(path);
    try {
      return doc.pages.length;
    } finally {
      await doc.dispose();
    }
  }

  Future<String> _save(PdfDocument doc, String dir, String fileName) async {
    final bytes = await doc.encodePdf();
    final outPath = await _files.uniquePath(dir, fileName);
    await File(outPath).writeAsBytes(bytes, flush: true);
    return outPath;
  }

  /// Joins [paths] into one PDF, in the given order.
  Future<String> merge(List<String> paths, String dir, String fileName) async {
    _init();
    final sources = <PdfDocument>[];
    PdfDocument? out;
    try {
      for (final p in paths) {
        sources.add(await open(p));
      }
      out = await PdfDocument.createNew(sourceName: fileName);
      out.pages = [for (final d in sources) ...d.pages];
      return await _save(out, dir, fileName);
    } finally {
      await out?.dispose();
      for (final d in sources) {
        await d.dispose();
      }
    }
  }

  /// Saves the chosen pages (1-based, in the order given) as one new PDF.
  Future<String> extract(String path, List<int> pages, String dir, String fileName) async {
    final source = await open(path);
    PdfDocument? out;
    try {
      out = await PdfDocument.createNew(sourceName: fileName);
      out.pages = [for (final n in pages) source.pages[n - 1]];
      return await _save(out, dir, fileName);
    } finally {
      await out?.dispose();
      await source.dispose();
    }
  }

  /// Saves each group of pages as its own PDF inside a new folder next to the
  /// original. Returns the folder's path.
  Future<String> splitToFolder(
      String path,
      List<List<int>> groups, {
        required String folderName,
        required String filePrefix,
        void Function(int done, int total)? onProgress,
      }) async {
    final dir = path.substring(0, path.lastIndexOf('/'));
    final folder = await _files.uniquePath(dir, folderName);
    await Directory(folder).create(recursive: true);

    final source = await open(path);
    try {
      for (var i = 0; i < groups.length; i++) {
        final out = await PdfDocument.createNew(sourceName: '$filePrefix ${i + 1}.pdf');
        try {
          out.pages = [for (final n in groups[i]) source.pages[n - 1]];
          final bytes = await out.encodePdf();
          final pad = groups.length.toString().length;
          final name = '$filePrefix ${(i + 1).toString().padLeft(pad, '0')}.pdf';
          await File('$folder/$name').writeAsBytes(bytes, flush: true);
        } finally {
          await out.dispose();
        }
        onProgress?.call(i + 1, groups.length);
      }
    } finally {
      await source.dispose();
    }
    return folder;
  }

  /// Rebuilds the PDF from [edits]: pages in this order, each turned
  /// clockwise by its number of quarter turns. Pages left out are deleted.
  Future<String> organize(
      String path,
      List<PageEdit> edits,
      String dir,
      String fileName,
      ) async {
    final source = await open(path);
    PdfDocument? out;
    try {
      out = await PdfDocument.createNew(sourceName: fileName);
      out.pages = [
        for (final e in edits)
              () {
            var page = source.pages[e.index];
            for (var i = 0; i < e.turns % 4; i++) {
              page = page.rotatedCW90();
            }
            return page;
          }(),
      ];
      return await _save(out, dir, fileName);
    } finally {
      await out?.dispose();
      await source.dispose();
    }
  }

  /// Draws one page. [scale] 1 = 72 dpi.
  static Future<img.Image> renderImage(PdfPage page, double scale) async {
    var w = (page.width * scale).round();
    var h = (page.height * scale).round();
    // Keep huge pages from using too much memory.
    const maxSide = 5000;
    final longest = w > h ? w : h;
    if (longest > maxSide) {
      final k = maxSide / longest;
      w = (w * k).round();
      h = (h * k).round();
    }
    final rendered = await page.render(width: w < 1 ? 1 : w, height: h < 1 ? 1 : h);
    if (rendered == null) throw const FormatException("Couldn't draw a page");
    try {
      return rendered.createImageNF();
    } finally {
      rendered.dispose();
    }
  }

  /// Draws one page as PNG bytes. [scale] 1 = 72 dpi.
  static Future<Uint8List> renderPng(PdfPage page, double scale) async {
    final image = await renderImage(page, scale);
    return Isolate.run(() => img.encodePng(image));
  }

  /// Saves the chosen pages as pictures in a new folder next to the PDF.
  /// Returns the folder's path.
  Future<String> toImages(
      String path,
      List<int> pages, {
        required bool jpg,
        required int dpi,
        void Function(int done, int total)? onProgress,
      }) async {
    final dir = path.substring(0, path.lastIndexOf('/'));
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final folder = await _files.uniquePath(dir, '$base images');
    await Directory(folder).create(recursive: true);

    final doc = await open(path);
    try {
      final pad = doc.pages.length.toString().length;
      for (var i = 0; i < pages.length; i++) {
        final n = pages[i];
        final image = await renderImage(doc.pages[n - 1], dpi / 72);
        final Uint8List bytes = await Isolate.run(
              () => jpg ? img.encodeJpg(image, quality: 90) : img.encodePng(image),
        );
        final file = '$base page ${n.toString().padLeft(pad, '0')}.${jpg ? 'jpg' : 'png'}';
        await File('$folder/$file').writeAsBytes(bytes, flush: true);
        onProgress?.call(i + 1, pages.length);
      }
    } finally {
      await doc.dispose();
    }
    return folder;
  }

  /// Saves the text of the PDF next to it as a .txt file. Scanned PDFs (just
  /// pictures of pages) have no text to read.
  Future<({String path, int pages, int characters})> toText(
      String path, {
        void Function(int done, int total)? onProgress,
      }) async {
    final dir = path.substring(0, path.lastIndexOf('/'));
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;

    final doc = await open(path);
    final buffer = StringBuffer();
    var pages = 0;
    try {
      final total = doc.pages.length;
      for (var i = 0; i < total; i++) {
        // dynamic: the result type differs slightly between pdfrx versions.
        final dynamic text = await doc.pages[i].loadText();
        final t = (text?.fullText as String?) ?? '';
        if (t.trim().isNotEmpty) {
          if (buffer.isNotEmpty) buffer.writeln('\n--- Page ${i + 1} ---\n');
          buffer.write(t.trim());
          pages++;
        }
        onProgress?.call(i + 1, total);
      }
    } finally {
      await doc.dispose();
    }

    if (buffer.isEmpty) {
      throw const FormatException('No text found. This PDF may be scanned pictures');
    }
    final outPath = await _files.uniquePath(dir, '$base.txt');
    await File(outPath).writeAsString(buffer.toString(), flush: true);
    return (path: outPath, pages: pages, characters: buffer.length);
  }
}

class PageEdit {
  PageEdit(this.index, {this.turns = 0});

  /// Zero-based page number in the original PDF.
  final int index;

  /// Clockwise quarter turns.
  int turns;
}

/// Reads "1-3, 5, 8-" into page numbers (1-based). "all" or empty means every
/// page. Throws a [FormatException] with a readable message.
List<int> parsePageRanges(String text, int count) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty || t == 'all') return [for (var i = 1; i <= count; i++) i];

  final pages = <int>[];
  for (final raw in t.split(RegExp(r'[,\s;]+'))) {
    if (raw.isEmpty) continue;
    final m = RegExp(r'^(\d*)-(\d*)$').firstMatch(raw);
    if (m != null && (m[1]!.isNotEmpty || m[2]!.isNotEmpty)) {
      final from = m[1]!.isEmpty ? 1 : int.parse(m[1]!);
      final to = m[2]!.isEmpty ? count : int.parse(m[2]!);
      if (from < 1 || to > count || from > to) {
        throw FormatException('"$raw" is outside this PDF (1 to $count)');
      }
      for (var i = from; i <= to; i++) {
        pages.add(i);
      }
      continue;
    }
    final n = int.tryParse(raw);
    if (n == null) throw FormatException('"$raw" is not a page number');
    if (n < 1 || n > count) {
      throw FormatException('Page $n is outside this PDF (1 to $count)');
    }
    pages.add(n);
  }
  if (pages.isEmpty) throw const FormatException('Enter the pages you want');
  return pages;
}