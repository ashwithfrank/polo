import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

import '../models/file_item.dart';
import 'file_service.dart';

enum ImageTarget { png, jpg, webp, bmp, gif, ico, tiff }

extension ImageTargetX on ImageTarget {
  String get ext => name;
  String get label => name.toUpperCase();

  /// Formats where the quality slider does something.
  bool get usesQuality => this == ImageTarget.jpg || this == ImageTarget.webp;

  /// The format for a file extension, or null if Polo can't write it.
  static ImageTarget? fromExtension(String ext) => switch (ext) {
    'png' => ImageTarget.png,
    'jpg' || 'jpeg' => ImageTarget.jpg,
    'webp' => ImageTarget.webp,
    'bmp' => ImageTarget.bmp,
    'gif' => ImageTarget.gif,
    'ico' => ImageTarget.ico,
    'tif' || 'tiff' => ImageTarget.tiff,
    _ => null,
  };
}

class ConvertResult {
  const ConvertResult({required this.path, required this.bytes});

  final String path;
  final int bytes;

  String get name => path.split('/').last;
}

class ConvertService {
  ConvertService(this._files);

  final FileService _files;

  /// Image types Polo can read.
  static const supportedInputs = {
    'png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif', 'tif', 'tiff', 'ico',
  };

  static bool canConvert(FileItem item) =>
      !item.isDirectory && supportedInputs.contains(item.extension);

  /// True when [item] is already in the [target] format.
  static bool isAlready(FileItem item, ImageTarget target) =>
      ImageTargetX.fromExtension(item.extension) == target;

  /// Converts and/or shrinks [item] and saves the result next to it, never
  /// overwriting an existing file.
  ///
  /// [target] null keeps the image's own format. [maxSide] limits the longest
  /// side in pixels (images are never enlarged).
  Future<ConvertResult> convertImage(
      FileItem item, {
        ImageTarget? target,
        int quality = 90,
        int? maxSide,
      }) async {
    final out = target ?? ImageTargetX.fromExtension(item.extension) ?? ImageTarget.png;
    final dir = item.parentPath;
    final dot = item.name.lastIndexOf('.');
    final base = dot > 0 ? item.name.substring(0, dot) : item.name;

    // Same format out as in: add a suffix so it doesn't clash with the original.
    final sameFormat = ImageTargetX.fromExtension(item.extension) == out;
    final outPath = await _files.uniquePath(
      dir,
      '${sameFormat ? '${base}_small' : base}.${out.ext}',
    );
    final inPath = item.path;

    // Decoding, resizing and encoding are heavy, so run them off the UI thread.
    var bytes = await Isolate.run(() => _processSync(inPath, out, quality, maxSide));

    if (out == ImageTarget.webp) {
      // The image package can't write WebP, so Android's own encoder does it.
      bytes = await FlutterImageCompress.compressWithList(
        bytes,
        format: CompressFormat.webp,
        quality: quality,
        // The defaults shrink big images; these values keep the size as is.
        minWidth: 100000,
        minHeight: 100000,
        autoCorrectionAngle: false,
        keepExif: false,
      );
    }

    await File(outPath).writeAsBytes(bytes, flush: true);
    return ConvertResult(path: outPath, bytes: bytes.length);
  }
}

/// Returns the encoded image. For WebP it returns a PNG that the caller
/// finishes with the native encoder.
Uint8List _processSync(String inPath, ImageTarget target, int quality, int? maxSide) {
  final bytes = File(inPath).readAsBytesSync();
  var image = img.decodeImage(bytes);
  if (image == null) {
    throw const FormatException("This image format isn't supported");
  }

  // Phone photos often store rotation in EXIF, so apply it before saving.
  image = img.bakeOrientation(image);

  // Icons can't be bigger than 256 pixels.
  var limit = maxSide;
  if (target == ImageTarget.ico && (limit == null || limit > 256)) limit = 256;

  if (limit != null && (image.width > limit || image.height > limit)) {
    image = image.width >= image.height
        ? img.copyResize(image, width: limit, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: limit, interpolation: img.Interpolation.average);
  }

  // JPG has no transparency, so flatten onto white.
  if (target == ImageTarget.jpg && image.hasAlpha) {
    final background = img.Image(width: image.width, height: image.height);
    img.fill(background, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(background, image);
    image = background;
  }

  return switch (target) {
    ImageTarget.png || ImageTarget.webp => img.encodePng(image),
    ImageTarget.jpg => img.encodeJpg(image, quality: quality),
    ImageTarget.bmp => img.encodeBmp(image),
    ImageTarget.gif => img.encodeGif(image),
    ImageTarget.ico => img.encodeIco(image),
    ImageTarget.tiff => img.encodeTiff(image),
  };
}