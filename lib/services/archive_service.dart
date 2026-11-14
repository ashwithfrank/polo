import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';

import '../models/file_item.dart';
import 'file_service.dart';

class ExtractResult {
  const ExtractResult({required this.folderPath, required this.fileCount});

  final String folderPath;
  final int fileCount;

  String get folderName => folderPath.split('/').last;
}

class ArchiveService {
  ArchiveService(this._files);

  final FileService _files;

  /// Compresses [items] (files and folders) into [fileName] inside [dir].
  /// Never overwrites: a taken name becomes "name (1).zip". Returns the path.
  Future<String> createZip(
      List<FileItem> items,
      String dir,
      String fileName,
      ) async {
    final outPath = await _files.uniquePath(dir, fileName);

    for (final item in items) {
      if (item.isDirectory && outPath.startsWith('${item.path}/')) {
        throw const FileSystemException(
          "Can't save the ZIP inside a folder you're compressing",
        );
      }
    }

    final paths = [for (final i in items) i.path];
    final isDir = [for (final i in items) i.isDirectory];
    await Isolate.run(() => _zipSync(paths, isDir, outPath));
    return outPath;
  }

  /// Extracts [item] into a new folder next to it, named after the ZIP.
  Future<ExtractResult> extractZip(FileItem item) async {
    final name = item.name;
    final base = name.toLowerCase().endsWith('.zip')
        ? name.substring(0, name.length - 4)
        : name;
    final outDir = await _files.uniquePath(
      item.parentPath,
      base.isEmpty ? 'Extracted' : base,
    );
    final zipPath = item.path;

    try {
      final count = await Isolate.run(() => _unzipSync(zipPath, outDir));
      return ExtractResult(folderPath: outDir, fileCount: count);
    } catch (_) {
      // Don't leave a half-extracted folder behind.
      try {
        Directory(outDir).deleteSync(recursive: true);
      } catch (_) {}
      rethrow;
    }
  }
}

Future<void> _zipSync(List<String> paths, List<bool> isDir, String outPath) async {
  final encoder = ZipFileEncoder();
  try {
    await (encoder.create(outPath) as dynamic);
    for (var i = 0; i < paths.length; i++) {
      if (isDir[i]) {
        await (encoder.addDirectory(Directory(paths[i])) as dynamic);
      } else {
        await (encoder.addFile(File(paths[i])) as dynamic);
      }
    }
    await (encoder.close() as dynamic);
  } catch (_) {
    try {
      File(outPath).deleteSync();
    } catch (_) {}
    rethrow;
  }
}

Future<int> _unzipSync(String zipPath, String outDir) async {
  await Directory(outDir).create(recursive: true);
  await (extractFileToDisk(zipPath, outDir) as dynamic);
  return Directory(outDir)
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .length;
}