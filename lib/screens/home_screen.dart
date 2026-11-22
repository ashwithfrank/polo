import 'package:flutter/material.dart';

import '../models/home_layout.dart';
import '../models/storage_category.dart';
import '../services/file_service.dart';
import '../services/settings_controller.dart';
import '../services/storage_controller.dart';
import '../services/storage_info.dart';
import '../services/storage_scanner.dart';
import '../utils/format.dart';
import '../widgets/file_tile.dart';
import '../widgets/message_view.dart';
import '../widgets/motion.dart';
import '../widgets/open_file.dart';
import 'customize_home_screen.dart';
import '../services/path_items.dart';
import '../widgets/quick_actions.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.settings,
    required this.onOpenFolder,
    required this.onOpenStorage,
    required this.onSearch,
    required this.onOpenCategory,
    required this.onOpenVault,
  });

  final StorageController controller;
  final SettingsController settings;
  final void Function(String path) onOpenFolder;
  final VoidCallback onOpenStorage;
  final VoidCallback onSearch;
  final void Function(StorageCategory category) onOpenCategory;
  final VoidCallback onOpenVault;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, settings]),
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

        final children = <Widget>[
          Reveal(index: 0, child: _SearchPill(onTap: onSearch)),
          const SizedBox(height: 16),
        ];
        var step = 1;
        for (final id in settings.homeOrder) {
          if (settings.isHomeHidden(id)) continue;
          final section = switch (id) {
            'storage' => Reveal(
                index: step,
                child: _StorageCard(
                  info: controller.info,
                  loading: controller.loading,
                  onTap: onOpenStorage,
                ),
              ),
            'vault' => Reveal(index: step, child: _VaultCard(onTap: onOpenVault)),
            'categories' => _categories(context, step, titleStyle),
            'quick' => _quick(context, step, titleStyle),
            'favorites' => _pathList(
                context,
                step,
                titleStyle,
                title: 'Favourites',
                paths: settings.favoriteFiles,
                empty: 'Star a file or folder from its ⋮ menu to keep it here.',
              ),
            'opened' => _pathList(
                context,
                step,
                titleStyle,
                title: 'Recently opened',
                paths: settings.openedFiles,
                empty: 'Files you open will show up here.',
                limit: 6,
                onClear: settings.clearOpened,
              ),
            'recent' => _recent(context, step, titleStyle, scan),
            _ => const SizedBox.shrink(),
          };
          children.add(KeyedSubtree(key: ValueKey(id), child: section));
          children.add(SizedBox(height: id == 'storage' ? 12 : 24));
          step++;
        }
        children.add(
          Align(
            alignment: Alignment.center,
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CustomizeHomeScreen(settings: settings)),
              ),
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Customize Home'),
            ),
          ),
        );

        return RefreshIndicator(
          onRefresh: controller.load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: children,
          ),
        );
      },
    );
  }

  Widget _categories(BuildContext context, int step, TextStyle? titleStyle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Reveal(index: step, child: Text('Categories', style: titleStyle)),
        const SizedBox(height: 10),
        Reveal(
          index: step,
          child: SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final c in StorageCategory.values.where((c) => c != StorageCategory.other))
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
        ),
      ],
    );
  }

  Widget _quick(BuildContext context, int step, TextStyle? titleStyle) {
    final scheme = Theme.of(context).colorScheme;
    // Presets keep their usual order; folders the user added follow.
    final saved = settings.quickFolders;
    final paths = [
      for (final p in quickPresets)
        if (saved.contains(p.path)) p.path,
      ...saved.where((f) => !isPresetFolder(f)),
    ];
    if (paths.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick access', style: titleStyle),
          const SizedBox(height: 8),
          Text(
            'No folders yet. Tap Customize Home to add some.',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Reveal(index: step, child: Text('Quick access', style: titleStyle)),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.1,
          children: [
            for (var qi = 0; qi < paths.length; qi++)
              Reveal(
                index: step + qi ~/ 3,
                child: PressScale(
                  child: Builder(builder: (context) {
                    final f = quickFolderFor(paths[qi], scheme.primary);
                    return _QuickTile(
                      label: f.label,
                      icon: f.icon,
                      color: f.color,
                      onTap: () => onOpenFolder('${FileService.rootPath}/${f.path}'),
                    );
                  }),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _pathList(
    BuildContext context,
    int step,
    TextStyle? titleStyle, {
    required String title,
    required List<String> paths,
    required String empty,
    int limit = 8,
    VoidCallback? onClear,
  }) {
    final items = itemsFromPaths(paths).take(limit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: titleStyle)),
            if (onClear != null && items.isNotEmpty)
              TextButton(onPressed: onClear, child: const Text('Clear')),
          ],
        ),
        const SizedBox(height: 4),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                empty,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          )
        else
          for (final (n, item) in items.indexed)
            Reveal(
              index: step + n,
              child: FileTile(
                item: item,
                onTap: () =>
                    item.isDirectory ? onOpenFolder(item.path) : openFile(context, item),
                onMore: () => showQuickActions(context, item),
              ),
            ),
      ],
    );
  }

  Widget _recent(BuildContext context, int step, TextStyle? titleStyle, ScanResult? scan) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          for (final (n, item) in scan.recent.take(8).indexed)
            Reveal(
              index: step + n,
              child: FileTile(item: item, onTap: () => openFile(context, item)),
            ),
      ],
    );
  }
}

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
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: i.usedFraction),
                    duration: motion(context, 800),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 8,
                      backgroundColor: fg.withValues(alpha: 0.3),
                      color: fg,
                    ),
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

class _VaultCard extends StatelessWidget {
  const _VaultCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressScale(
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.lock_outline, color: scheme.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Vault', style: TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        'Keep private files locked with a password',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onSurface.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
