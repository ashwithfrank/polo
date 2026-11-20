import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../models/home_layout.dart';
import '../services/file_service.dart';
import '../services/settings_controller.dart';
import '../widgets/polo_message.dart';
import 'pick_files_screen.dart';

/// Choose which blocks Home shows, in what order, and which folders sit in
/// Quick access.
class CustomizeHomeScreen extends StatelessWidget {
  const CustomizeHomeScreen({super.key, required this.settings});

  final SettingsController settings;

  Future<void> _addFolder(BuildContext context) async {
    final picked = await Navigator.of(context).push<List<FileItem>>(
      MaterialPageRoute(
        builder: (_) => PickFilesScreen(
          title: 'Choose a folder',
          accepts: (_) => false,
          selectFolders: true,
        ),
      ),
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;

    final root = '${FileService.rootPath}/';
    final abs = picked.first.path;
    if (!abs.startsWith(root) || abs.length <= root.length) {
      showPoloMessage(context, 'Choose a folder in your internal storage');
      return;
    }
    final rel = abs.substring(root.length);
    if (settings.quickFolders.contains(rel)) {
      showPoloMessage(context, 'That folder is already there');
      return;
    }
    await settings.setQuickFolders([...settings.quickFolders, rel]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customize Home'),
        actions: [
          TextButton(onPressed: settings.resetHome, child: const Text('Reset')),
        ],
      ),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final order = settings.homeOrder;
          final folders = settings.quickFolders;
          final customs = folders.where((f) => !isPresetFolder(f)).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(
                'Drag to reorder. Turn a block off to hide it. The search bar always stays on top.',
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65), fontSize: 13),
              ),
              const SizedBox(height: 12),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: order.length,
                onReorderItem: (oldIndex, newIndex) {
                  final list = List.of(order);
                  list.insert(newIndex, list.removeAt(oldIndex));
                  settings.setHomeOrder(list);
                },
                itemBuilder: (context, i) {
                  final section = homeSectionFor(order[i]);
                  final hidden = settings.isHomeHidden(section.id);
                  return Container(
                    key: ValueKey(section.id),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListTile(
                      leading: Icon(
                        section.icon,
                        color: hidden ? scheme.onSurface.withValues(alpha: 0.4) : scheme.primary,
                      ),
                      title: Text(
                        section.label,
                        style: TextStyle(
                          color: hidden ? scheme.onSurface.withValues(alpha: 0.5) : null,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: !hidden,
                            onChanged: (on) => settings.setHomeSectionHidden(section.id, !on),
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.drag_handle),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Text('Quick access folders', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Pick the shortcuts you want, or add any folder.',
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65), fontSize: 13),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final p in quickPresets)
                    FilterChip(
                      avatar: Icon(p.icon, size: 18, color: p.color),
                      label: Text(p.label),
                      selected: folders.contains(p.path),
                      onSelected: (on) => settings.setQuickFolders(
                        on ? [...folders, p.path] : folders.where((f) => f != p.path).toList(),
                      ),
                    ),
                  for (final c in customs)
                    InputChip(
                      avatar: Icon(Icons.folder_outlined, size: 18, color: scheme.primary),
                      label: Text(quickFolderFor(c, scheme.primary).label),
                      onDeleted: () =>
                          settings.setQuickFolders(folders.where((f) => f != c).toList()),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('Add folder'),
                    onPressed: () => _addFolder(context),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}