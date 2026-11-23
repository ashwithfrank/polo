import 'dart:io';

import 'package:flutter/services.dart';

import 'file_service.dart';
import 'output_location.dart';

/// One picture taken out of a PDF.
class ExtractedPicture {
  const ExtractedPicture(this.name, this.width, this.height);

  final String name;
  final int width;
  final int height;
}

/// Takes the pictures out of a PDF at the size they are stored, with Android code.
class PdfImagesService {
  PdfImagesService(this._files);

  final FileService _files;

  static const _channel = MethodChannel('com.aos.polo/pdflock');

  /// Saves the pictures on [pages] into a new folder next to the PDF.
  /// Returns the folder and what was saved. The folder is removed when
  /// there was nothing to save.
  Future<({String folder, List<ExtractedPicture> pictures})> extract(
    String path,
    List<int> pages,
  ) async {
    final dir = path.substring(0, path.lastIndexOf('/'));
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final folder = await _files.uniquePath(
      await OutputLocation.resolve(dir, OutputKind.images),
      '$base pictures',
    );
    await Directory(folder).create(recursive: true);

    try {
      final lines = await _channel.invokeListMethod<String>('extractImages', {
            'input': path,
            'outDir': folder,
            'pages': pages,
          }) ??
          const <String>[];
      final pictures = <ExtractedPicture>[];
      for (final line in lines) {
        final parts = line.split('|');
        if (parts.length != 3) continue;
        pictures.add(ExtractedPicture(parts[0], int.tryParse(parts[1]) ?? 0, int.tryParse(parts[2]) ?? 0));
        OutputLocation.announce('$folder/${parts[0]}');
      }
      if (pictures.isEmpty) {
        await Directory(folder).delete(recursive: true);
      }
      return (folder: folder, pictures: pictures);
    } on PlatformException catch (e) {
      await Directory(folder).delete(recursive: true);
      throw FormatException(
        e.code == 'wrong_password'
            ? 'This PDF has a password. Unlock it first with Lock or unlock PDF'
            : "Couldn't take the pictures out of this PDF",
      );
    } on MissingPluginException {
      await Directory(folder).delete(recursive: true);
      throw const FormatException('This needs the latest Polo build');
    }
  }
}
