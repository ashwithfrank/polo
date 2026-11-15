import 'dart:io';

import '../models/file_item.dart';

enum RenameMode { numbering, replace, addText, changeCase }

enum CaseStyle { lower, upper, title }

/// Everything the user can choose on the batch rename screen.
class RenameOptions {
  const RenameOptions({
    this.mode = RenameMode.numbering,
    this.base = '',
    this.start = 1,
    this.find = '',
    this.replaceWith = '',
    this.prefix = '',
    this.suffix = '',
    this.caseStyle = CaseStyle.lower,
  });

  final RenameMode mode;
  final String base;
  final int start;
  final String find;
  final String replaceWith;
  final String prefix;
  final String suffix;
  final CaseStyle caseStyle;
}

/// Splits a name into the part that gets renamed and the extension, which is
/// always kept as it is. Folders have no extension.
(String stem, String ext) splitName(FileItem item) {
  final name = item.name;
  if (item.isDirectory) return (name, '');
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return (name, '');
  return (name.substring(0, dot), name.substring(dot));
}

String _titleCase(String s) => s.toLowerCase().replaceAllMapped(
  RegExp(r'(^|[\s_\-])([a-z])'),
      (m) => '${m[1]}${m[2]!.toUpperCase()}',
);

/// The new name for the item at [index] of [count].
String newNameFor(FileItem item, int index, int count, RenameOptions o) {
  final (stem, ext) = splitName(item);

  final String newStem;
  switch (o.mode) {
    case RenameMode.numbering:
      final last = o.start + count - 1;
      final width = last.toString().length;
      final number = (o.start + index).toString().padLeft(width, '0');
      newStem = '${o.base}$number';
    case RenameMode.replace:
      newStem = o.find.isEmpty ? stem : stem.replaceAll(o.find, o.replaceWith);
    case RenameMode.addText:
      newStem = '${o.prefix}$stem${o.suffix}';
    case RenameMode.changeCase:
      newStem = switch (o.caseStyle) {
        CaseStyle.lower => stem.toLowerCase(),
        CaseStyle.upper => stem.toUpperCase(),
        CaseStyle.title => _titleCase(stem),
      };
  }
  return '$newStem$ext';
}

/// Why [name] can't be used for [item], or null if it's fine.
String? invalidReason(FileItem item, String name) {
  final (_, ext) = splitName(item);
  // A name that is only the extension (".jpg") counts as empty.
  if (name.trim().isEmpty || name == ext) return 'Empty name';
  if (name.contains('/')) return "Names can't contain /";
  if (name.length > 255) return 'Name is too long';
  return null;
}

/// Renames [items] to [newNames] (same order). Done in two steps through
/// temporary names so swaps and overlaps like a to b, b to c, work. If
/// anything fails, everything is put back.
Future<void> applyRenames(List<FileItem> items, List<String> newNames) async {
  final stamp = DateTime.now().microsecondsSinceEpoch;

  Future<void> move(String from, String to, bool isDir) async {
    if (isDir) {
      await Directory(from).rename(to);
    } else {
      await File(from).rename(to);
    }
  }

  final temps = <int, String>{};
  final finished = <int, String>{};
  try {
    for (var i = 0; i < items.length; i++) {
      if (items[i].name == newNames[i]) continue;
      final temp = '${items[i].parentPath}/.polo_rename_${stamp}_$i';
      await move(items[i].path, temp, items[i].isDirectory);
      temps[i] = temp;
    }
    for (final i in temps.keys.toList()) {
      final target = '${items[i].parentPath}/${newNames[i]}';
      await move(temps[i]!, target, items[i].isDirectory);
      temps.remove(i);
      finished[i] = target;
    }
  } catch (_) {
    // Put everything back the way it was.
    for (final e in finished.entries) {
      try {
        await move(e.value, items[e.key].path, items[e.key].isDirectory);
      } catch (_) {}
    }
    for (final e in temps.entries) {
      try {
        await move(e.value, items[e.key].path, items[e.key].isDirectory);
      } catch (_) {}
    }
    rethrow;
  }
}