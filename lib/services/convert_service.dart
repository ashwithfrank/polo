import 'dart:io';
import 'dart:isolate';

import 'package:image/image.dart' as img;

import '../models/file_item.dart';
import 'file_service.dart';

enum ImageTarget { png, jpg }

extension ImageTargetX on ImageTarget {
  String get ext => name;
  String get label => name.toUpperCase();
}

class ConvertService {
  ConvertService(this._files);

  final FileService _files;

  /// Image types Polo can read. (WebP can be read but not written yet.)
  static const supportedInputs = {'png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'};

  static bool canConvert(FileItem item) =>
      !item.isDirectory && supportedInputs.contains(item.extension);

  /// True when [item] is already in the [target] format.
  static bool isAlready(FileItem item, ImageTarget target) {
    final ext = item.extension == 'jpeg' ? 'jpg' : item.extension;
    return ext == target.ext;
  }

  /// Converts [item] and saves the result next to it, never overwriting an
  /// existing file. Returns the path of the new file.
  Future<String> convertImage(
    FileItem item,
    ImageTarget target, {
    int quality = 90,
  }) async {
    final dir = item.path.substring(0, item.path.lastIndexOf('/'));
    final dot = item.name.lastIndexOf('.');
    final base = dot > 0 ? item.name.substring(0, dot) : item.name;
    final outPath = await _files.uniquePath(dir, '$base.${target.ext}');
    final inPath = item.path;

    // Decoding and encoding are heavy, so run them off the UI thread.
    await Isolate.run(() => _convertSync(inPath, outPath, target, quality));
    return outPath;
  }
}

void _convertSync(String inPath, String outPath, ImageTarget target, int quality) {
  final bytes = File(inPath).readAsBytesSync();
  var image = img.decodeImage(bytes);
  if (image == null) {
    throw const FormatException("This image format isn't supported");
  }

  // Phone photos often store rotation in EXIF, so apply it before saving.
  image = img.bakeOrientation(image);

  // JPG has no transparency, so flatten onto white.
  if (target == ImageTarget.jpg && image.hasAlpha) {
    final background = img.Image(width: image.width, height: image.height);
    img.fill(background, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(background, image);
    image = background;
  }

  final out = target == ImageTarget.png
      ? img.encodePng(image)
      : img.encodeJpg(image, quality: quality);
  File(outPath).writeAsBytesSync(out);
}