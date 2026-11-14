import 'dart:convert';
import 'dart:io';

import '../models/file_item.dart';
import 'file_service.dart';

class TrashEntry {
  const TrashEntry({
    required this.id,
    required this.name,
    required this.originalPath,
    required this.isDirectory,
    required this.size,
    required this.deletedAt,
  });

  final String id;
  final String name;
  final String originalPath;
  final bool isDirectory;
  final int size;
  final DateTime deletedAt;

  String get originalParent => originalPath.substring(0, originalPath.lastIndexOf('/'));

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'originalPath': originalPath,
    'isDirectory': isDirectory,
    'size': size,
    'deletedAt': deletedAt.millisecondsSinceEpoch,
  };

  static TrashEntry fromJson(Map<String, dynamic> j) => TrashEntry(
    id: j['id'] as String,
    name: j['name'] as String,
    originalPath: j['originalPath'] as String,
    isDirectory: j['isDirectory'] as bool,
    size: (j['size'] as num).toInt(),
    deletedAt: DateTime.fromMillisecondsSinceEpoch((j['deletedAt'] as num).toInt()),
  );
}

/// A simple recycle bin. Deleted items are moved into a hidden folder on the
/// same storage volume (so the move is instant) and listed in an index file.
class TrashService {
  TrashService([FileService? files]) : _files = files ?? FileService();

  static const retentionDays = 30;
  static const trashDir = '${FileService.rootPath}/.Polo_Trash';
  static const _filesDir = '$trashDir/files';
  static const _indexPath = '$trashDir/index.json';

  final FileService _files;

  Future<List<TrashEntry>> _readIndex() async {
    final file = File(_indexPath);
    if (!await file.exists()) return [];
    try {
      final data = jsonDecode(await file.readAsString()) as List;
      return [
        for (final e in data) TrashEntry.fromJson((e as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeIndex(List<TrashEntry> entries) async {
    await Directory(trashDir).create(recursive: true);
    // Keeps the trash out of gallery apps.
    final nomedia = File('$trashDir/.nomedia');
    if (!await nomedia.exists()) await nomedia.create();
    final tmp = File('$_indexPath.tmp');
    await tmp.writeAsString(jsonEncode([for (final e in entries) e.toJson()]));
    await tmp.rename(_indexPath);
  }

  /// Newest first.
  Future<List<TrashEntry>> list() async {
    final entries = await _readIndex();
    // Forget entries whose files have gone missing.
    final alive = <TrashEntry>[];
    for (final e in entries) {
      if (await FileSystemEntity.type('$_filesDir/${e.id}/${e.name}', followLinks: false) !=
          FileSystemEntityType.notFound) {
        alive.add(e);
      }
    }
    alive.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return alive;
  }

  FileItem asFileItem(TrashEntry e) => FileItem(
    path: '$_filesDir/${e.id}/${e.name}',
    name: e.name,
    isDirectory: e.isDirectory,
    size: e.size,
    modified: e.deletedAt,
  );

  /// Moves [item] into the trash. Throws [FileSystemException] on failure.
  Future<TrashEntry> moveToTrash(FileItem item) async {
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    final dir = '$_filesDir/$id';
    await Directory(dir).create(recursive: true);
    try {
      await _files.move(item, dir);
    } catch (_) {
      try {
        await Directory(dir).delete(recursive: true);
      } catch (_) {}
      rethrow;
    }
    final entry = TrashEntry(
      id: id,
      name: item.name,
      originalPath: item.path,
      isDirectory: item.isDirectory,
      size: item.size,
      deletedAt: DateTime.now(),
    );
    final entries = await _readIndex();
    await _writeIndex([...entries, entry]);
    return entry;
  }

  Future<void> _remove(TrashEntry entry) async {
    final dir = Directory('$_filesDir/${entry.id}');
    if (await dir.exists()) await dir.delete(recursive: true);
    final entries = await _readIndex();
    await _writeIndex(entries.where((e) => e.id != entry.id).toList());
  }

  /// Puts the item back where it came from. If that name is taken now it
  /// becomes "name (1)". Returns the restored path.
  Future<String> restore(TrashEntry entry) async {
    final parent = entry.originalParent;
    await Directory(parent).create(recursive: true);
    final target = await _files.uniquePath(parent, entry.name);
    final item = asFileItem(entry);
    await _files.move(item, parent);
    // move() picks the same unique name, so the result matches [target].
    await _remove(entry);
    return target;
  }

  Future<void> deleteForever(TrashEntry entry) => _remove(entry);

  Future<void> empty() async {
    final dir = Directory(trashDir);
    if (!await dir.exists()) return;
    if (await Directory(_filesDir).exists()) {
      await Directory(_filesDir).delete(recursive: true);
    }
    await _writeIndex([]);
  }

  /// Permanently removes anything older than [retentionDays].
  Future<void> purgeOld() async {
    final cutoff = DateTime.now().subtract(const Duration(days: retentionDays));
    for (final e in await _readIndex()) {
      if (e.deletedAt.isBefore(cutoff)) {
        try {
          await _remove(e);
        } catch (_) {}
      }
    }
  }
}