import 'dart:io';
import 'dart:isolate';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'file_service.dart';

enum PdfPageMode { a4, a5, letter, fit }

enum PdfOrientation { auto, portrait, landscape }

enum PdfMargin {
  none(0, 'None'),
  small(12, 'Small'),
  normal(24, 'Normal'),
  large(48, 'Large');

  const PdfMargin(this.points, this.label);
  final double points;
  final String label;
}

class PdfService {
  PdfService(this._files);

  final FileService _files;

  /// Builds a PDF with one page per image, in the given order, and saves it
  /// as [fileName] inside [dir] (never overwriting). Returns the saved path.
  Future<String> imagesToPdf({
    required List<String> imagePaths,
    required String dir,
    required String fileName,
    required PdfPageMode mode,
    required int quality,
    PdfOrientation orientation = PdfOrientation.auto,
    PdfMargin margin = PdfMargin.normal,
  }) async {
    final outPath = await _files.uniquePath(dir, fileName);
    // Decoding photos is heavy, so build the whole PDF off the UI thread.
    await Isolate.run(
          () => _buildPdf(imagePaths, outPath, mode, quality, orientation, margin),
    );
    return outPath;
  }
}

Future<void> _buildPdf(
    List<String> paths,
    String outPath,
    PdfPageMode mode,
    int quality,
    PdfOrientation orientation,
    PdfMargin pageMargin,
    ) async {
  final doc = pw.Document();

  for (final path in paths) {
    var image = img.decodeImage(File(path).readAsBytesSync());
    if (image == null) {
      throw FormatException("Couldn't read ${path.split('/').last}");
    }

    // Apply EXIF rotation, and flatten transparency onto white.
    image = img.bakeOrientation(image);
    if (image.hasAlpha) {
      final background = img.Image(width: image.width, height: image.height);
      img.fill(background, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(background, image);
      image = background;
    }

    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final pdfImage = pw.MemoryImage(img.encodeJpg(image, quality: quality));

    final PdfPageFormat format;
    final double margin;
    if (mode != PdfPageMode.fit) {
      final base = switch (mode) {
        PdfPageMode.a5 => PdfPageFormat.a5,
        PdfPageMode.letter => PdfPageFormat.letter,
        _ => PdfPageFormat.a4,
      };
      final landscape = switch (orientation) {
        PdfOrientation.auto => w > h,
        PdfOrientation.portrait => false,
        PdfOrientation.landscape => true,
      };
      format = landscape ? base.landscape : base.portrait;
      margin = pageMargin.points;
    } else {
      // Page matches the image's shape, with the long side set to A4's.
      const longSide = 842.0;
      final scale = longSide / (w > h ? w : h);
      format = PdfPageFormat(w * scale, h * scale);
      margin = 0;
    }

    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.all(margin),
        build: (_) => pw.Center(
          child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
        ),
      ),
    );
  }

  File(outPath).writeAsBytesSync(await doc.save());
}