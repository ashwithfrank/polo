import 'package:flutter/material.dart';

import '../models/file_item.dart';

class FileTile extends StatelessWidget {
  const FileTile({
    super.key,
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
  });

  final FileItem item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = _iconFor(item.kind, scheme);

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: selected,
      selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.7),
      leading: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: selected
            ? Container(
                key: const ValueKey('selected'),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.check, color: scheme.onPrimary, size: 22),
              )
            : Container(
                key: const ValueKey('normal'),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
      ),
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        item.isDirectory ? item.dateLabel : '${item.sizeLabel} · ${item.dateLabel}',
        style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 12),
      ),
    );
  }

  (IconData, Color) _iconFor(FileKind kind, ColorScheme scheme) {
    return switch (kind) {
      FileKind.folder => (Icons.folder_rounded, scheme.primary),
      FileKind.image => (Icons.image_outlined, Colors.pink),
      FileKind.video => (Icons.movie_outlined, Colors.deepPurple),
      FileKind.audio => (Icons.audiotrack_outlined, Colors.teal),
      FileKind.pdf => (Icons.picture_as_pdf_outlined, Colors.red),
      FileKind.document => (Icons.description_outlined, Colors.blue),
      FileKind.archive => (Icons.folder_zip_outlined, Colors.amber.shade800),
      FileKind.apk => (Icons.android, Colors.green),
      FileKind.other => (Icons.insert_drive_file_outlined, scheme.onSurface.withValues(alpha: 0.6)),
    };
  }
}