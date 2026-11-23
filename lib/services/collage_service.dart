import 'dart:io';
import 'dart:isolate';

import 'package:image/image.dart' as img;

import '../models/file_item.dart';
import 'file_service.dart';
import 'output_location.dart';

enum CollageLayout {
  grid('Grid'),
  row('Row'),
  column('Column');

  const CollageLayout(this.label);
  final String label;

  int columns(int n) => switch (this) {
        CollageLayout.grid => n <= 1 ? 1 : (n <= 4 ? 2 : 3),
        CollageLayout.row => n,
        CollageLayout.column => 1,
      };

  int rows(int n) => (n / columns(n)).ceil();
}

/// Puts several pictures on one picture.
class CollageService {
  CollageService(this._files);

  final FileService _files;

  /// Saves the collage next to the first picture and returns its path.
  Future<String> make(
    List<FileItem> pictures,
    CollageLayout layout,
    int gap,
    int background,
    bool png,
  ) async {
    final paths = [for (final p in pictures) p.path];
    final cols = layout.columns(paths.length);
    final rows = layout.rows(paths.length);
    final bytes = await Isolate.run(
      () => _collageSync(paths, cols, rows, gap, background, png),
    );
    final dir = await OutputLocation.resolve(pictures.first.parentPath, OutputKind.images);
    final out = await _files.uniquePath(dir, 'Collage.${png ? 'png' : 'jpg'}');
    await File(out).writeAsBytes(bytes, flush: true);
    OutputLocation.announce(out);
    return out;
  }
}

List<int> _collageSync(List<String> paths, int cols, int rows, int gap, int bg, bool png) {
  // Pick a cell size that keeps the whole picture around 2000 pixels.
  final byWidth = (2000 - gap * (cols + 1)) ~/ cols;
  final byHeight = (2600 - gap * (rows + 1)) ~/ rows;
  final cell = byWidth < byHeight ? byWidth : byHeight;
  final width = cols * cell + (cols + 1) * gap;
  final height = rows * cell + (rows + 1) * gap;

  final canvas = img.Image(width: width, height: height);
  img.fill(canvas, color: img.ColorRgb8((bg >> 16) & 0xFF, (bg >> 8) & 0xFF, bg & 0xFF));

  for (var i = 0; i < paths.length; i++) {
    var pic = img.decodeImage(File(paths[i]).readAsBytesSync());
    if (pic == null) continue;
    pic = img.bakeOrientation(pic);
    // Fill the square, cropping the middle of whatever sticks out.
    pic = pic.width < pic.height
        ? img.copyResize(pic, width: cell, interpolation: img.Interpolation.average)
        : img.copyResize(pic, height: cell, interpolation: img.Interpolation.average);
    final x0 = (pic.width - cell) ~/ 2;
    final y0 = (pic.height - cell) ~/ 2;
    pic = img.copyCrop(pic, x: x0, y: y0, width: cell, height: cell);
    final col = i % cols;
    final row = i ~/ cols;
    img.compositeImage(
      canvas,
      pic,
      dstX: gap + col * (cell + gap),
      dstY: gap + row * (cell + gap),
    );
  }
  return png ? img.encodePng(canvas) : img.encodeJpg(canvas, quality: 90);
}
