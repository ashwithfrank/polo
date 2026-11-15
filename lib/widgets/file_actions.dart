import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/file_item.dart';
import '../screens/batch_rename_screen.dart';
import '../services/archive_service.dart';
import '../services/file_service.dart';
import '../services/trash_service.dart';
import 'name_dialog.dart';
import 'progress_dialog.dart';
import 'polo_message.dart';

// Actions on a list of files, shared by the category and search screens.
// Each one asks and reports by itself; the caller only refreshes its list.

void _toast(BuildContext context, String message) {
  showPoloMessage(context, message);
}

String _count(int n) => '$n ${n == 1 ? 'item' : 'items'}';

Future<void> shareFiles(BuildContext context, List<FileItem> items) async {
  final files = items.where((i) => !i.isDirectory).toList();
  if (files.isEmpty) {
    _toast(context, "Folders can't be shared. Select files instead");
    return;
  }
  await SharePlus.instance.share(
    ShareParams(files: [for (final f in files) XFile(f.path)]),
  );
}

/// Asks, then moves [items] to the trash. Returns the ones that were moved.
Future<List<FileItem>> trashFiles(BuildContext context, List<FileItem> items) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Move ${_count(items.length)} to trash?'),
      content: Text(
        'You can restore them from Trash (in Settings) for ${TrashService.retentionDays} days.',
      ),
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
  if (ok != true || !context.mounted) return const [];

  final trash = TrashService();
  final moved = <FileItem>[];
  final detail = ValueNotifier<String>('');
  String? error;
  await runWithProgress(context, 'Moving to trash…', () async {
    for (var i = 0; i < items.length; i++) {
      detail.value = '${i + 1} of ${items.length} · ${items[i].name}';
      try {
        await trash.moveToTrash(items[i]);
        moved.add(items[i]);
      } on FileSystemException catch (e) {
        error = e.osError?.message ?? e.message;
      }
    }
  }, detail: detail);

  if (context.mounted) {
    _toast(context, error ?? 'Moved ${_count(moved.length)} to trash');
  }
  return moved;
}

/// Asks for a name, then zips [items] next to the first one. True if created.
Future<bool> zipFiles(BuildContext context, List<FileItem> items) async {
  final first = items.first;
  final dot = first.name.lastIndexOf('.');
  final base = first.isDirectory || dot <= 0 ? first.name : first.name.substring(0, dot);

  final name = await showDialog<String>(
    context: context,
    builder: (_) => NameDialog(
      title: 'Compress to ZIP',
      confirmLabel: 'Compress',
      initial: items.length == 1 ? base : 'Archive',
      hint: 'File name',
      suffix: '.zip',
      existing: const {},
    ),
  );
  if (name == null || !context.mounted) return false;

  try {
    final out = await runWithProgress(
      context,
      'Compressing…',
          () => ArchiveService(FileService()).createZip(items, first.parentPath, '$name.zip'),
    );
    if (context.mounted) _toast(context, 'Created ${out.split('/').last}');
    return true;
  } catch (e) {
    if (context.mounted) {
      _toast(context, e is FileSystemException ? e.message : "Couldn't create the ZIP");
    }
    return false;
  }
}

/// Opens the rename screen for [items]. True if anything was renamed.
Future<bool> renameFiles(BuildContext context, List<FileItem> items) async {
  final renamed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => BatchRenameScreen(items: items)),
  );
  return renamed == true;
}