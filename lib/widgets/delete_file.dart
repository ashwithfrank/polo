import 'dart:io';

import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/trash_service.dart';

/// Asks before moving [item] to the trash. Returns true if it was moved.
Future<bool> deleteFileWithConfirm(BuildContext context, FileItem item) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Move to trash?'),
      content: Text('${item.name} (${item.sizeLabel}) will go to the trash. You can restore it for ${TrashService.retentionDays} days.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          child: const Text('Move to trash'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;

  void toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  try {
    await TrashService().moveToTrash(item);
    if (context.mounted) toast('Moved ${item.name} to trash');
    return true;
  } on FileSystemException catch (e) {
    if (context.mounted) toast(e.osError?.message ?? e.message);
    return false;
  }
}