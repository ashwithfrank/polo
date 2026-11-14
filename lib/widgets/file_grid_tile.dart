import 'dart:io';

import 'package:flutter/material.dart';

import '../models/file_item.dart';
import 'file_tile.dart';

/// A square-ish tile for grid view: a big preview (the picture itself for
/// images) with the name underneath.
class FileGridTile extends StatelessWidget {
  const FileGridTile({
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
    final (icon, color) = fileIconFor(item.kind, scheme);

    final iconBox = Container(
      color: color.withValues(alpha: 0.15),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 40),
    );

    final Widget preview = item.kind == FileKind.image
        ? Image.file(
      File(item.path),
      fit: BoxFit.cover,
      cacheWidth: 360,
      filterQuality: FilterQuality.low,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => iconBox,
    )
        : iconBox;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(14), child: preview),
                if (selected)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: scheme.primary, width: 2),
                    ),
                  ),
                if (selected)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: scheme.primary,
                      child: Icon(Icons.check, size: 14, color: scheme.onPrimary),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, height: 1.15),
          ),
          const SizedBox(height: 2),
          Text(
            item.isDirectory ? item.dateLabel : item.sizeLabel,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}