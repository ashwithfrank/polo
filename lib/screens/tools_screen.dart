import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/convert_service.dart';
import 'convert_images_screen.dart';
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
        const _ToolCard(
          icon: Icons.picture_as_pdf_outlined,
          title: 'Images to PDF',
          subtitle: '',
        ),
        const _ToolCard(
          icon: Icons.folder_zip_outlined,
          title: 'Zip and unzip',
          subtitle: '',
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