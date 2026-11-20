import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

import '../models/file_item.dart';
import 'convert_service.dart';
import 'file_service.dart';
import './output_location.dart';

/// What to do to a picture. Turns are clockwise quarter turns. The crop is
/// given as fractions (0 to 1) of the picture AFTER turning and flipping.
class EditPlan {
  const EditPlan({
    this.quarterTurns = 0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.cropLeft = 0,
    this.cropTop = 0,
    this.cropRight = 1,
    this.cropBottom = 1,
  });

  final int quarterTurns;
  final bool flipHorizontal;
  final bool flipVertical;
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;

  bool get isCropped =>
      cropLeft > 0.0005 || cropTop > 0.0005 || cropRight < 0.9995 || cropBottom < 0.9995;

  bool get isEmpty =>
      quarterTurns % 4 == 0 && !flipHorizontal && !flipVertical && !isCropped;
}

class EditImageService {
  EditImageService(this._files);

  final FileService _files;

  /// Formats Polo can edit and write back in the same format.
  static const editableInputs = {'jpg', 'jpeg', 'png', 'webp', 'bmp'};

  static bool canEdit(FileItem item) =>
      !item.isDirectory && editableInputs.contains(item.extension);

  /// Applies [plan] and saves the result next to the original as
  /// "name_edited.ext". Never overwrites. Returns the new file's path.
  Future<ConvertResult> edit(FileItem item, EditPlan plan) async {
    final ext = item.extension == 'jpeg' ? 'jpg' : item.extension;
    final dot = item.name.lastIndexOf('.');
    final base = dot > 0 ? item.name.substring(0, dot) : item.name;
    final outPath = await _files.uniquePath(await OutputLocation.resolve(item.parentPath, OutputKind.images), '${base}_edited.$ext');
    final inPath = item.path;

    var bytes = await Isolate.run(() => _editSync(inPath, ext, plan));

    if (ext == 'webp') {
      // The image package can't write WebP, so Android's own encoder does it.
      bytes = await FlutterImageCompress.compressWithList(
        bytes,
        format: CompressFormat.webp,
        quality: 95,
        minWidth: 100000,
        minHeight: 100000,
        autoCorrectionAngle: false,
        keepExif: false,
      );
    }

    await File(outPath).writeAsBytes(bytes, flush: true);
    OutputLocation.announce(outPath);
    return ConvertResult(path: outPath, bytes: bytes.length);
  }
}

Uint8List _editSync(String inPath, String ext, EditPlan plan) {
  final decoded = img.decodeImage(File(inPath).readAsBytesSync());
  if (decoded == null) {
    throw const FormatException("This image format isn't supported");
  }
  // Apply the phone's rotation first, so what you saw is what gets edited.
  var image = img.bakeOrientation(decoded);

  final turns = plan.quarterTurns % 4;
  if (turns != 0) {
    final clockwise = _rotatesClockwise();
    image = img.copyRotate(
      image,
      angle: clockwise ? turns * 90 : (4 - turns) * 90,
    );
  }
  if (plan.flipHorizontal) {
    image = img.flip(
      image,
      direction: _flipIsLeftRight() ? img.FlipDirection.horizontal : img.FlipDirection.vertical,
    );
  }
  if (plan.flipVertical) {
    image = img.flip(
      image,
      direction: _flipIsLeftRight() ? img.FlipDirection.vertical : img.FlipDirection.horizontal,
    );
  }

  if (plan.isCropped) {
    final w = image.width;
    final h = image.height;
    final x = (plan.cropLeft * w).round().clamp(0, w - 1).toInt();
    final y = (plan.cropTop * h).round().clamp(0, h - 1).toInt();
    final right = (plan.cropRight * w).round().clamp(x + 1, w).toInt();
    final bottom = (plan.cropBottom * h).round().clamp(y + 1, h).toInt();
    image = img.copyCrop(image, x: x, y: y, width: right - x, height: bottom - y);
  }

  return switch (ext) {
    'jpg' => img.encodeJpg(image.hasAlpha ? _flatten(image) : image, quality: 95),
    'bmp' => img.encodeBmp(image),
    _ => img.encodePng(image), // PNG, and WebP (finished by the caller)
  };
}

img.Image _flatten(img.Image image) {
  final background = img.Image(width: image.width, height: image.height);
  img.fill(background, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(background, image);
  return background;
}

// The image package's rotate and flip directions are checked against a tiny
// test picture, so the result is right whichever way the package defines them.

/// A 2x1 picture: red on the left, blue on the right.
img.Image _testPicture() {
  final t = img.Image(width: 2, height: 1);
  t.setPixelRgb(0, 0, 255, 0, 0);
  t.setPixelRgb(1, 0, 0, 0, 255);
  return t;
}

/// True if copyRotate with a positive angle turns the picture clockwise.
bool _rotatesClockwise() {
  // Clockwise: the left pixel ends up on top, so (0,0) stays red.
  final r = img.copyRotate(_testPicture(), angle: 90);
  return r.getPixel(0, 0).r > 128;
}

/// True if FlipDirection.horizontal mirrors left and right.
bool _flipIsLeftRight() {
  final f = img.flip(_testPicture(), direction: img.FlipDirection.horizontal);
  return f.getPixel(0, 0).b > 128;
}
