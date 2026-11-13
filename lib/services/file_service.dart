import 'dart:io';

import '../models/file_item.dart';

enum SortBy { name, date, size }

class FileService {
  static const rootPath = '/storage/emulated/0';

  /// Lists a directory: folders first, then files, in the chosen order.
  /// Throws [FileSystemException] if the directory can't be read.
  Future<List<FileItem>> list(
    String path, {
    required SortBy sortBy,
    required bool showHidden,
  }) async {
    final items = <FileItem>[];

    await for (final entity in Directory(path).list(followLinks: false)) {
      final name = entity.path.split('/').last;
      if (!showHidden && name.startsWith('.')) continue;
      try {
        final stat = await entity.stat();
        items.add(FileItem(
          path: entity.path,
          name: name,
          isDirectory: stat.type == FileSystemEntityType.directory,
          size: stat.size,
          modified: stat.modified,
        ));
      } on FileSystemException {
        continue;
      }
    }

    items.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      switch (sortBy) {
        case SortBy.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SortBy.date:
          return b.modified.compareTo(a.modified);
        case SortBy.size:
          return b.size.compareTo(a.size);
      }
    });

    return items;
  }

  // ---------------------------------------------------------------------------
  // File actions. All of these throw FileSystemException on failure.
  // ---------------------------------------------------------------------------

  Future<bool> _exists(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    return type != FileSystemEntityType.notFound;
  }

  String _parentOf(String path) => path.substring(0, path.lastIndexOf('/'));

  /// Returns a path in [dir] for [name] that doesn't exist yet, adding
  /// " (1)", " (2)" and so on before the extension when needed.
  Future<String> uniquePath(String dir, String name) async {
    var candidate = '$dir/$name';
    if (!await _exists(candidate)) return candidate;

    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var i = 1;
    while (true) {
      candidate = '$dir/$base ($i)$ext';
      if (!await _exists(candidate)) return candidate;
      i++;
    }
  }

  void _guardInto(FileItem item, String destDir) {
    if (item.isDirectory &&
        (destDir == item.path || destDir.startsWith('${item.path}/'))) {
      throw FileSystemException("Can't put a folder inside itself", item.path);
    }
  }

  Future<void> _copyDir(Directory src, String dest) async {
    await Directory(dest).create(recursive: true);
    await for (final entity in src.list(followLinks: false)) {
      final target = '$dest/${entity.path.split('/').last}';
      if (entity is Directory) {
        await _copyDir(entity, target);
      } else if (entity is File) {
        await entity.copy(target);
      }
    }
  }

  Future<void> _copyTo(FileItem item, String target) async {
    if (item.isDirectory) {
      await _copyDir(Directory(item.path), target);
    } else {
      await File(item.path).copy(target);
    }
  }

  Future<void> _deletePath(FileItem item) async {
    if (item.isDirectory) {
      await Directory(item.path).delete(recursive: true);
    } else {
      await File(item.path).delete();
    }
  }

  Future<void> copy(FileItem item, String destDir) async {
    _guardInto(item, destDir);
    final target = await uniquePath(destDir, item.name);
    await _copyTo(item, target);
  }

  Future<void> move(FileItem item, String destDir) async {
    if (_parentOf(item.path) == destDir) return;
    _guardInto(item, destDir);
    final target = await uniquePath(destDir, item.name);
    try {
      if (item.isDirectory) {
        await Directory(item.path).rename(target);
      } else {
        await File(item.path).rename(target);
      }
    } on FileSystemException {
      // rename can fail across volumes, so fall back to copy then delete.
      await _copyTo(item, target);
      await _deletePath(item);
    }
  }

  Future<void> rename(FileItem item, String newName) async {
    final target = '${_parentOf(item.path)}/$newName';
    if (await _exists(target)) {
      throw FileSystemException('That name is already taken', target);
    }
    if (item.isDirectory) {
      await Directory(item.path).rename(target);
    } else {
      await File(item.path).rename(target);
    }
  }

  Future<void> delete(FileItem item) => _deletePath(item);

  Future<void> createFolder(String parent, String name) async {
    final target = '$parent/$name';
    if (await _exists(target)) {
      throw FileSystemException('That name is already taken', target);
    }
    await Directory(target).create();
  }
}