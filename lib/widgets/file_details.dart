import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/file_item.dart';
import '../utils/format.dart';
import '../utils/paths.dart';

class _FolderStats {
  const _FolderStats(this.files, this.folders, this.bytes);
  final int files;
  final int folders;
  final int bytes;
}

_FolderStats _measure(String path) {
  var files = 0, folders = 0, bytes = 0;
  try {
    for (final e in Directory(path).listSync(recursive: true, followLinks: false)) {
      try {
        if (e is File) {
          files++;
          bytes += e.lengthSync();
        } else if (e is Directory) {
          folders++;
        }
      } catch (_) {}
    }
  } catch (_) {}
  return _FolderStats(files, folders, bytes);
}

String _two(int n) => n.toString().padLeft(2, '0');

String _dateTime(DateTime t) =>
    '${t.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][t.month - 1]} ${t.year}, ${_two(t.hour)}:${_two(t.minute)}';

String _typeLabel(FileItem item) {
  if (item.isDirectory) return 'Folder';
  final ext = item.extension.toUpperCase();
  final kind = switch (item.kind) {
    FileKind.image => 'Image',
    FileKind.video => 'Video',
    FileKind.audio => 'Audio',
    FileKind.pdf => 'PDF document',
    FileKind.document => 'Document',
    FileKind.archive => 'Archive',
    FileKind.apk => 'Android app',
    _ => 'File',
  };
  return ext.isEmpty ? kind : '$kind · $ext';
}

/// Shows name, type, location, size and dates for [item].
///
/// For a trashed item, pass [originalPath] and [deletedAt] so the dialog shows
/// where it came from and when it was deleted.
Future<void> showFileDetails(
    BuildContext context,
    FileItem item, {
      String? originalPath,
      DateTime? deletedAt,
    }) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DetailsDialog(
      item: item,
      originalPath: originalPath,
      deletedAt: deletedAt,
    ),
  );
}

class _DetailsDialog extends StatefulWidget {
  const _DetailsDialog({required this.item, this.originalPath, this.deletedAt});

  final FileItem item;
  final String? originalPath;
  final DateTime? deletedAt;

  @override
  State<_DetailsDialog> createState() => _DetailsDialogState();
}

class _DetailsDialogState extends State<_DetailsDialog> {
  Future<_FolderStats>? _stats;

  @override
  void initState() {
    super.initState();
    if (widget.item.isDirectory) {
      final path = widget.item.path;
      _stats = Isolate.run(() => _measure(path));
    }
  }

  Widget _row(String label, String value, {bool copy = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 2),
          copy ? SelectableText(value) : Text(value),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return AlertDialog(
      title: const Text('Details'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Name', item.name, copy: true),
            _row('Type', _typeLabel(item)),
            _row('Location', folderLabelFor(widget.originalPath ?? item.path), copy: true),
            if (!item.isDirectory)
              _row('Size', '${formatBytes(item.size)} (${item.size} bytes)')
            else
              FutureBuilder<_FolderStats>(
                future: _stats,
                builder: (context, snap) {
                  final s = snap.data;
                  if (s == null) {
                    return _row('Size', 'Calculating…');
                  }
                  String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row('Size', formatBytes(s.bytes)),
                      _row(
                        'Contains',
                        '${plural(s.files, 'file', 'files')}, ${plural(s.folders, 'folder', 'folders')}',
                      ),
                    ],
                  );
                },
              ),
            widget.deletedAt != null
                ? _row('Deleted', _dateTime(widget.deletedAt!))
                : _row('Modified', _dateTime(item.modified)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: widget.originalPath ?? item.path));
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('Path copied')));
          },
          child: const Text('Copy path'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}