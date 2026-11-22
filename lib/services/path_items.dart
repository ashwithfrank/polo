import 'dart:io';

import '../models/file_item.dart';

/// Turns saved paths back into files, skipping any that no longer exist.
List<FileItem> itemsFromPaths(Iterable<String> paths) {
  final out = <FileItem>[];
  for (final path in paths) {
    try {
      final type = FileSystemEntity.typeSync(path);
      if (type == FileSystemEntityType.notFound) continue;
      final stat = FileStat.statSync(path);
      out.add(FileItem(
        path: path,
        name: path.split('/').last,
        isDirectory: type == FileSystemEntityType.directory,
        size: stat.size,
        modified: stat.modified,
      ));
    } catch (_) {}
  }
  return out;
}
