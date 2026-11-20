import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../screens/apk_analyzer_screen.dart';
import '../screens/compare_screen.dart';
import '../screens/batch_rename_screen.dart';
import '../screens/checksum_screen.dart';
import '../screens/convert_images_screen.dart';
import '../screens/edit_image_screen.dart';
import '../screens/photo_info_screen.dart';
import '../screens/strip_metadata_screen.dart';
import '../services/image_edit_service.dart';
import '../services/image_meta.dart';
import '../screens/images_to_pdf_screen.dart';
import '../screens/pdf_merge_screen.dart';
import '../screens/pdf_organize_screen.dart';
import '../screens/pdf_split_screen.dart';
import '../screens/pdf_to_images_screen.dart';
import '../screens/text_to_pdf_screen.dart';
import '../services/pdf_tools_service.dart';
import '../widgets/open_file.dart';
import '../widgets/pdf_result.dart';
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

Future<void> runCompressForSharing(BuildContext context) async {
  final picked = await Navigator.of(context).push<List<FileItem>>(
    MaterialPageRoute(
      builder: (_) => const PickFilesScreen(
        title: 'Choose photos',
        accepts: ConvertService.canConvert,
      ),
    ),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ConvertImagesScreen(files: picked, keepFormat: true, share: true),
    ),
  );
}

Future<void> runEditImage(BuildContext context) async {
  final picked = await Navigator.of(context).push<List<FileItem>>(
    MaterialPageRoute(
      builder: (_) => const PickFilesScreen(
        title: 'Choose a picture',
        accepts: EditImageService.canEdit,
        single: true,
      ),
    ),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => EditImageScreen(item: picked.first)),
  );
}

Future<void> runPhotoInfo(BuildContext context) async {
  final picked = await Navigator.of(context).push<List<FileItem>>(
    MaterialPageRoute(
      builder: (_) => const PickFilesScreen(
        title: 'Choose a photo',
        accepts: ConvertService.canConvert,
        single: true,
      ),
    ),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => PhotoInfoScreen(item: picked.first)),
  );
}

bool _canStrip(FileItem item) =>
    !item.isDirectory && strippableExtensions.contains(item.extension);

Future<void> runStripMetadata(BuildContext context) async {
  final picked = await Navigator.of(context).push<List<FileItem>>(
    MaterialPageRoute(
      builder: (_) => const PickFilesScreen(
        title: 'Choose pictures',
        accepts: _canStrip,
      ),
    ),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => StripMetadataScreen(files: picked)),
  );
}

// ---------- PDF tools ----------

bool _isPdf(FileItem item) => !item.isDirectory && item.extension == 'pdf';

Future<List<FileItem>?> _pickPdfs(
    BuildContext context, {
      required String title,
      bool single = false,
    }) {
  return Navigator.of(context).push<List<FileItem>>(
    MaterialPageRoute(
      builder: (_) => PickFilesScreen(title: title, accepts: _isPdf, single: single),
    ),
  );
}

Future<void> runMergePdfs(BuildContext context) async {
  final picked = await _pickPdfs(context, title: 'Choose PDFs to merge');
  if (picked == null || picked.isEmpty || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => PdfMergeScreen(files: picked)),
  );
}

Future<void> runSplitPdf(BuildContext context) async {
  final picked = await _pickPdfs(context, title: 'Choose a PDF', single: true);
  if (picked == null || picked.isEmpty || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => PdfSplitScreen(item: picked.first)),
  );
}

Future<void> runOrganizePdf(BuildContext context) async {
  final picked = await _pickPdfs(context, title: 'Choose a PDF', single: true);
  if (picked == null || picked.isEmpty || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => PdfOrganizeScreen(item: picked.first)),
  );
}

Future<void> runPdfToImages(BuildContext context) async {
  final picked = await _pickPdfs(context, title: 'Choose a PDF', single: true);
  if (picked == null || picked.isEmpty || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => PdfToImagesScreen(item: picked.first)),
  );
}

Future<void> runPdfToText(BuildContext context) async {
  final picked = await _pickPdfs(context, title: 'Choose a PDF', single: true);
  if (picked == null || picked.isEmpty || !context.mounted) return;
  await pdfToText(context, picked.first);
}

/// Saves the text of [item] next to it. Used by the tool and Quick Actions.
Future<void> pdfToText(BuildContext context, FileItem item) async {
  final picked = [item];
  final detail = ValueNotifier<String>('');
  try {
    final result = await runWithProgress(
      context,
      'Reading text…',
          () => PdfToolsService(FileService()).toText(
        picked.first.path,
        onProgress: (done, total) => detail.value = 'Page $done of $total',
      ),
      detail: detail,
    );
    if (!context.mounted) return;
    showPoloMessage(
      context,
      'Saved ${result.path.split('/').last}',
      actionLabel: 'Open',
      onAction: () => openFile(
        context,
        FileItem(
          path: result.path,
          name: result.path.split('/').last,
          isDirectory: false,
          size: 0,
          modified: DateTime.now(),
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    showPoloMessage(
      context,
      e is FormatException ? e.message : "Couldn't read this PDF",
    );
  } finally {
    detail.dispose();
  }
}

const _textExtensions = {
  'txt', 'md', 'markdown', 'csv', 'json', 'log', 'xml', 'yml', 'yaml', 'ini', 'html',
};

bool _isTextFile(FileItem item) =>
    !item.isDirectory && _textExtensions.contains(item.extension);

Future<void> runTextToPdf(BuildContext context) async {
  final fromFile = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('From a text or Markdown file'),
            onTap: () => Navigator.pop(sheet, true),
          ),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: const Text('Type or paste text'),
            onTap: () => Navigator.pop(sheet, false),
          ),
        ],
      ),
    ),
  );
  if (fromFile == null || !context.mounted) return;

  if (!fromFile) {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TextToPdfScreen()),
    );
    return;
  }

  final picked = await Navigator.of(context).push<List<FileItem>>(
    MaterialPageRoute(
      builder: (_) => const PickFilesScreen(
        title: 'Choose a text file',
        accepts: _isTextFile,
        single: true,
      ),
    ),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;

  if (!context.mounted) return;
  await textFileToPdf(context, picked.first);
}

/// Opens the text-to-PDF screen filled with the text of [item].
Future<void> textFileToPdf(BuildContext context, FileItem item) async {
  if (item.size > 2 * 1024 * 1024) {
    showPoloMessage(context, 'That file is too big (2 MB is the limit)');
    return;
  }
  final text = utf8.decode(await File(item.path).readAsBytes(), allowMalformed: true);
  if (!context.mounted) return;

  final isMarkdown = item.extension == 'md' || item.extension == 'markdown';
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TextToPdfScreen(
        initialText: text,
        name: baseName(item.name),
        dir: item.parentPath,
        markdown: isMarkdown,
      ),
    ),
  );
}

Future<void> runApkAnalyzer(BuildContext context) async {
  final picked = await Navigator.of(context).push<List<FileItem>>(
    MaterialPageRoute(
      builder: (_) => PickFilesScreen(
        title: 'Choose an APK',
        accepts: (item) => item.extension == 'apk',
        single: true,
      ),
    ),
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;

  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => ApkAnalyzerScreen(item: picked.first)),
  );
}

Future<void> runCompare(BuildContext context) async {
  List<FileItem>? picked;
  while (true) {
    picked = await Navigator.of(context).push<List<FileItem>>(
      MaterialPageRoute(
        builder: (_) => const PickFilesScreen(
          title: 'Choose two files to compare',
          accepts: _acceptAll,
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    if (picked.length == 2) break;
    showPoloMessage(context, 'Pick exactly two files');
  }

  final two = picked;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => CompareScreen(a: two[0], b: two[1])),
  );
}