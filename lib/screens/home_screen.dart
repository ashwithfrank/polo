import 'package:flutter/material.dart';

import '../models/storage_category.dart';
import '../services/file_service.dart';
import '../services/storage_controller.dart';
import '../services/storage_info.dart';
import '../utils/format.dart';
import '../widgets/file_tile.dart';
import '../widgets/message_view.dart';
import '../widgets/open_file.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.onOpenFolder,
    required this.onOpenStorage,
    required this.onSearch,
    required this.onOpenCategory,
  });

  final StorageController controller;
  final void Function(String path) onOpenFolder;
  final VoidCallback onOpenStorage;
  final VoidCallback onSearch;
  final void Function(StorageCategory category) onOpenCategory;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.needsAccess) {
          return MessageView(
            icon: Icons.folder_special_outlined,
            title: 'Allow access to your files',
            body: 'Polo needs permission to see your files so it can show your storage and recent files.',
            actionLabel: 'Grant access',
            onAction: controller.requestAccess,
          );
        }

        final scan = controller.scan;
        final titleStyle = Theme.of(context).textTheme.titleSmall;

        return RefreshIndicator(
          onRefresh: controller.load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _SearchPill(onTap: onSearch),
              const SizedBox(height: 16),
              _StorageCard(
                info: controller.info,
                loading: controller.loading,
                onTap: onOpenStorage,
              ),
              const SizedBox(height: 24),
              Text('Categories', style: titleStyle),
              const SizedBox(height: 10),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final c in StorageCategory.values
                        .where((c) => c != StorageCategory.other))
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: Icon(c.icon, size: 18, color: c.color),
                          label: Text(c.label),
                          onPressed: () => onOpenCategory(c),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('Quick access', style: titleStyle),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.1,
                children: [
                  for (final q in _quickAccess)
                    _QuickTile(
                      label: q.label,
                      icon: q.icon,
                      color: q.color,
                      onTap: () => onOpenFolder('${FileService.rootPath}/${q.folder}'),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Recent files', style: titleStyle),
              const SizedBox(height: 4),
              if (scan == null && controller.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Looking through your files…'),
                    ],
                  ),
                )
              else if (scan == null || scan.recent.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No recent files yet.')),
                )
              else
                for (final item in scan.recent.take(8))
                  FileTile(item: item, onTap: () => openFile(context, item)),
            ],
          ),
        );
      },
    );
  }
}

final _quickAccess = <({String label, IconData icon, String folder, Color color})>[
  (label: 'Downloads', icon: Icons.download_outlined, folder: 'Download', color: Colors.green),
  (label: 'Camera', icon: Icons.photo_camera_outlined, folder: 'DCIM/Camera', color: Colors.pink),
  (label: 'Pictures', icon: Icons.image_outlined, folder: 'Pictures', color: Colors.orange),
  (label: 'Documents', icon: Icons.description_outlined, folder: 'Documents', color: Colors.blue),
  (label: 'Music', icon: Icons.music_note_outlined, folder: 'Music', color: Colors.teal),
  (label: 'Movies', icon: Icons.movie_outlined, folder: 'Movies', color: Colors.deepPurple),
];

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.search, color: scheme.onSurface.withValues(alpha: 0.6)),
              const SizedBox(width: 12),
              Text(
                'Search files and folders',
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StorageCard extends StatelessWidget {
  const _StorageCard({required this.info, required this.loading, required this.onTap});

  final StorageInfo? info;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final i = info;
    final fg = scheme.onPrimary;

    return Material(
      color: scheme.primary,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Internal storage', style: TextStyle(color: fg.withValues(alpha: 0.85))),
                  const Spacer(),
                  Icon(Icons.chevron_right, color: fg.withValues(alpha: 0.85)),
                ],
              ),
              const SizedBox(height: 6),
              if (i != null) ...[
                Text(
                  '${formatBytes(i.used)} used',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: fg),
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: i.usedFraction,
                    minHeight: 8,
                    backgroundColor: fg.withValues(alpha: 0.3),
                    color: fg,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${formatBytes(i.free)} free of ${formatBytes(i.total)}',
                  style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 13),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    loading ? 'Checking your storage…' : 'Storage details unavailable',
                    style: TextStyle(color: fg, fontSize: 16),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}