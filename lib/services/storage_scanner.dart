import 'dart:io';
import 'dart:isolate';

import '../models/file_item.dart';
import '../models/storage_category.dart';
import 'file_service.dart';

class ScanResult {
  const ScanResult({
    required this.bytes,
    required this.counts,
    required this.largest,
    required this.recent,
    required this.index,
  });

  final Map<StorageCategory, int> bytes;
  final Map<StorageCategory, int> counts;
  final List<FileItem> largest;
  final List<FileItem> recent;

  /// Every file and folder found. Used by search and the category screens.
  final List<FileItem> index;

  int get totalBytes => bytes.values.fold(0, (a, b) => a + b);
  int get totalFiles => counts.values.fold(0, (a, b) => a + b);
}

class StorageScanner {
  /// Walks internal storage in a background isolate.
  static Future<ScanResult> scan() => Isolate.run(_scanSync);
}

ScanResult _scanSync() {
  const root = FileService.rootPath;
  const largeThreshold = 20 * 1024 * 1024;

  // Other apps' private folders can't be read, so skip them.
  const skipped = {'$root/Android/data', '$root/Android/obb'};

  final bytes = {for (final c in StorageCategory.values) c: 0};
  final counts = {for (final c in StorageCategory.values) c: 0};
  final largest = <FileItem>[];
  final recent = <FileItem>[];
  final index = <FileItem>[];

  int bySize(FileItem a, FileItem b) => b.size.compareTo(a.size);
  int byDate(FileItem a, FileItem b) => b.modified.compareTo(a.modified);

  final stack = <String>[root];
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();

    List<FileSystemEntity> entries;
    try {
      entries = Directory(dir).listSync(followLinks: false);
    } catch (_) {
      continue;
    }

    for (final entity in entries) {
      final name = entity.path.substring(entity.path.lastIndexOf('/') + 1);

      if (entity is Directory) {
        if (name.startsWith('.') || skipped.contains(entity.path)) continue;
        stack.add(entity.path);
        try {
          index.add(FileItem(
            path: entity.path,
            name: name,
            isDirectory: true,
            size: 0,
            modified: entity.statSync().modified,
          ));
        } catch (_) {}
      } else if (entity is File) {
        FileStat stat;
        try {
          stat = entity.statSync();
        } catch (_) {
          continue;
        }

        final item = FileItem(
          path: entity.path,
          name: name,
          isDirectory: false,
          size: stat.size,
          modified: stat.modified,
        );

        index.add(item);
        final category = StorageCategory.of(item.kind);
        bytes[category] = bytes[category]! + stat.size;
        counts[category] = counts[category]! + 1;

        if (stat.size >= largeThreshold) {
          largest.add(item);
          if (largest.length > 100) {
            largest.sort(bySize);
            largest.removeRange(40, largest.length);
          }
        }

        if (!name.startsWith('.')) {
          recent.add(item);
          if (recent.length > 200) {
            recent.sort(byDate);
            recent.removeRange(60, recent.length);
          }
        }
      }
    }
  }

  largest.sort(bySize);
  recent.sort(byDate);

  return ScanResult(
    bytes: bytes,
    counts: counts,
    largest: largest.take(25).toList(),
    recent: recent.take(15).toList(),
    index: index,
  );
}