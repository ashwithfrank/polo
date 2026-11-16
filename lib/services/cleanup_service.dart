import 'dart:io';
import 'dart:isolate';

import '../models/file_item.dart';
import 'file_service.dart';
import 'storage_scanner.dart';

/// Finds files for the cleanup tools. Nothing here deletes anything.
class CleanupService {
  /// Every visible file in internal storage.
  static Future<List<FileItem>> allFiles() async {
    final scan = await StorageScanner.scan();
    return [
      for (final i in scan.index)
        if (!i.isDirectory && !i.name.startsWith('.')) i,
    ];
  }

  /// Every file inside the Download folder, including sub-folders.
  static Future<List<FileItem>> downloads() => Isolate.run(_downloadsSync);

  /// Size of everything directly inside [path], biggest first.
  static Future<List<SizeEntry>> folderSizes(String path) =>
      Isolate.run(() => _folderSizesSync(path));
}

List<FileItem> _downloadsSync() {
  final out = <FileItem>[];
  final stack = <String>['${FileService.rootPath}/Download'];
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    List<FileSystemEntity> entries;
    try {
      entries = Directory(dir).listSync(followLinks: false);
    } catch (_) {
      continue;
    }
    for (final e in entries) {
      final name = e.path.substring(e.path.lastIndexOf('/') + 1);
      if (e is Directory) {
        stack.add(e.path);
      } else if (e is File) {
        try {
          final stat = e.statSync();
          out.add(FileItem(
            path: e.path,
            name: name,
            isDirectory: false,
            size: stat.size,
            modified: stat.modified,
          ));
        } catch (_) {}
      }
    }
  }
  return out;
}

class SizeEntry {
  const SizeEntry({required this.item, required this.bytes, required this.files});

  final FileItem item;
  final int bytes;
  final int files;
}

List<SizeEntry> _folderSizesSync(String path) {
  List<FileSystemEntity> children;
  try {
    children = Directory(path).listSync(followLinks: false);
  } catch (_) {
    return const [];
  }

  final out = <SizeEntry>[];
  for (final e in children) {
    final name = e.path.substring(e.path.lastIndexOf('/') + 1);
    try {
      if (e is File) {
        final stat = e.statSync();
        out.add(SizeEntry(
          item: FileItem(
            path: e.path,
            name: name,
            isDirectory: false,
            size: stat.size,
            modified: stat.modified,
          ),
          bytes: stat.size,
          files: 1,
        ));
      } else if (e is Directory) {
        var bytes = 0;
        var files = 0;
        final stack = <String>[e.path];
        while (stack.isNotEmpty) {
          final dir = stack.removeLast();
          List<FileSystemEntity> inner;
          try {
            inner = Directory(dir).listSync(followLinks: false);
          } catch (_) {
            continue;
          }
          for (final x in inner) {
            if (x is Directory) {
              stack.add(x.path);
            } else if (x is File) {
              try {
                bytes += x.lengthSync();
                files++;
              } catch (_) {}
            }
          }
        }
        out.add(SizeEntry(
          item: FileItem(
            path: e.path,
            name: name,
            isDirectory: true,
            size: 0,
            modified: e.statSync().modified,
          ),
          bytes: bytes,
          files: files,
        ));
      }
    } catch (_) {}
  }
  out.sort((a, b) => b.bytes.compareTo(a.bytes));
  return out;
}