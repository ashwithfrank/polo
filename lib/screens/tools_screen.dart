import 'dart:io';

import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/convert_service.dart';
import 'convert_images_screen.dart';
import 'duplicates_screen.dart';
import '../services/archive_service.dart';
import '../services/file_service.dart';
import '../widgets/name_dialog.dart';
import '../widgets/progress_dialog.dart';
import 'images_to_pdf_screen.dart';
import 'pick_files_screen.dart';

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  Future<void> _convertImages(BuildContext context) async {
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

  Future<void> _imagesToPdf(BuildContext context) async {
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

  Future<void> _zipTools(BuildContext context) async {
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
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
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

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      padding: const EdgeInsets.all(16),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.05,
      children: [
        _ToolCard(
          icon: Icons.transform,
          title: 'Convert images',
          subtitle: 'PNG and JPG',
          onTap: () => _convertImages(context),
        ),
        _ToolCard(
          icon: Icons.picture_as_pdf_outlined,
          title: 'Images to PDF',
          subtitle: 'Combine images',
          onTap: () => _imagesToPdf(context),
        ),
        _ToolCard(
          icon: Icons.folder_zip_outlined,
          title: 'Zip and unzip',
          subtitle: 'Compress and extract',
          onTap: () => _zipTools(context),
        ),
        _ToolCard(
          icon: Icons.content_copy_outlined,
          title: 'Duplicate finder',
          subtitle: 'Free up space',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DuplicatesScreen()),
          ),
        ),
        const _ToolCard(
          icon: Icons.audiotrack_outlined,
          title: 'Video to audio',
          subtitle: '',
        ),
      ],
    );
  }
}

bool _acceptAll(FileItem item) => true;

bool _isZip(FileItem item) => !item.isDirectory && item.extension == 'zip';

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: scheme.primary),
                ),
                const Spacer(),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  enabled ? subtitle : 'Coming soon',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}