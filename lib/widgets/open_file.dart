import 'dart:io';

import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../screens/viewer/viewer_screen.dart';
import '../services/file_service.dart';
import 'open_external.dart';
import '../services/settings_controller.dart';

/// Opens a file. Images, videos, audio and text open in Polo's own viewer;
/// everything else opens in another app.
///
/// Returns the files that were moved to the trash from inside the viewer, so
/// the caller can refresh its list.
Future<List<FileItem>> openFile(BuildContext context, FileItem item) async {
  SettingsController.current?.noteOpened(item.path);
  if (!canView(item)) {
    await openExternally(context, item);
    return const [];
  }

  var items = [item];
  if (item.kind == FileKind.image) {
    // Let the user swipe through the other images in the same folder.
    try {
      final all = await FileService().list(
        item.parentPath,
        sortBy: SortBy.name,
        showHidden: false,
      );
      final images = all.where((f) => f.kind == FileKind.image).toList();
      if (images.any((f) => f.path == item.path)) items = images;
    } on FileSystemException {
      // Fall back to just this image.
    }
  }
  if (!context.mounted) return const [];

  final deleted = <FileItem>[];
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ViewerScreen(
        items: items,
        initialIndex: items.indexWhere((f) => f.path == item.path),
        onDeleted: deleted.add,
      ),
    ),
  );
  return deleted;
}
