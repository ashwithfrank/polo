import 'dart:io';

import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../screens/batch_rename_screen.dart';
import '../screens/checksum_screen.dart';
import '../screens/convert_images_screen.dart';
import '../screens/images_to_pdf_screen.dart';
import '../screens/pick_files_screen.dart';
import '../services/archive_service.dart';
import '../services/convert_service.dart';
import '../services/file_service.dart';
import '../widgets/name_dialog.dart';
import '../widgets/progress_dialog.dart';
import '../widgets/polo_message.dart';

// What each tool does when it is tapped. The list of tools is in
// tools_registry.dart.

Future<void> runConvertImages(BuildContext context) async {
  final picked = await Navigator.of(context).push<List<FileItem>>(
    MaterialPageRoute(
      builder: (_) => const PickFilesScreen(
        title: 'Choose images',
        accepts: ConvertService.canConvert,
      ),
    ),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => ConvertImagesScreen(files: picked)),
  );
}

Future<void> runResizeImages(BuildContext context) async {
  final picked = await Navigator.of(context).push<List<FileItem>>(
    MaterialPageRoute(
      builder: (_) => const PickFilesScreen(
        title: 'Choose images',
        accepts: ConvertService.canConvert,
      ),
    ),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ConvertImagesScreen(files: picked, keepFormat: true),
    ),
  );
}

Future<void> runImagesToPdf(BuildContext context) async {
  final picked = await Navigator.of(context).push<List<FileItem>>(
    MaterialPageRoute(
      builder: (_) => const PickFilesScreen(
        title: 'Choose images',
        accepts: ConvertService.canConvert,
      ),
    ),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => ImagesToPdfScreen(files: picked)),
  );
}

Future<void> runZipTools(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.folder_zip_outlined),
            title: const Text('Create a ZIP'),
            subtitle: const Text('Compress files and folders'),
            onTap: () => Navigator.pop(context, 'create'),
          ),
          ListTile(
            leading: const Icon(Icons.unarchive_outlined),
            title: const Text('Extract a ZIP'),
            subtitle: const Text('Unpack a .zip file'),
            onTap: () => Navigator.pop(context, 'extract'),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  final service = ArchiveService(FileService());
  void toast(String message) {
    showPoloMessage(context, message);
  }

  if (choice == 'create') {
    final picked = await Navigator.of(context).push<List<FileItem>>(
      MaterialPageRoute(
        builder: (_) => const PickFilesScreen(
          title: 'Choose items to compress',
          accepts: _acceptAll,
          selectFolders: true,
        ),
      ),
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;

    final first = picked.first;
    final dot = first.name.lastIndexOf('.');
    final base = first.isDirectory || dot <= 0 ? first.name : first.name.substring(0, dot);

    final name = await showDialog<String>(
      context: context,
      builder: (_) => NameDialog(
        title: 'Compress to ZIP',
        confirmLabel: 'Compress',
        initial: picked.length == 1 ? base : 'Archive',
        hint: 'File name',
        suffix: '.zip',
        existing: const {},
      ),
    );
    if (name == null || !context.mounted) return;

    try {
      final out = await runWithProgress(
        context,
        'Compressing…',
            () => service.createZip(picked, first.parentPath, '$name.zip'),
      );
      if (context.mounted) toast('Created ${out.split('/').last}');
    } catch (e) {
      if (context.mounted) {
        toast(e is FileSystemException ? e.message : "Couldn't create the ZIP");
      }
    }
  } else {
    final picked = await Navigator.of(context).push<List<FileItem>>(
      MaterialPageRoute(
        builder: (_) => const PickFilesScreen(
          title: 'Choose a ZIP file',
          accepts: _isZip,
        ),
      ),
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;

    var done = 0;
    String? lastFolder;
    String? error;
    await runWithProgress(context, 'Extracting…', () async {
      for (final zip in picked) {
        try {
          final result = await service.extractZip(zip);
          lastFolder = result.folderName;
          done++;
        } catch (_) {
          error = "Couldn't extract ${zip.name}. It may be damaged or password protected.";
        }
      }
    });
    if (!context.mounted) return;
    toast(error ??
        (done == 1 ? 'Extracted to $lastFolder' : 'Extracted $done ZIP files'));
  }
}

Future<void> runBatchRename(BuildContext context) async {
  final picked = await Navigator.of(context).push<List<FileItem>>(
    MaterialPageRoute(
      builder: (_) => const PickFilesScreen(
        title: 'Choose files to rename',
        accepts: _acceptAll,
        selectFolders: true,
      ),
    ),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => BatchRenameScreen(items: picked)),
  );
}

Future<void> runChecksum(BuildContext context) async {
  final picked = await Navigator.of(context).push<List<FileItem>>(
    MaterialPageRoute(
      builder: (_) => const PickFilesScreen(
        title: 'Choose a file',
        accepts: _acceptAll,
        single: true,
      ),
    ),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => ChecksumScreen(file: picked.first)),
  );
}

bool _acceptAll(FileItem item) => true;

bool _isZip(FileItem item) => !item.isDirectory && item.extension == 'zip';