import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/path_items.dart';
import '../services/settings_controller.dart';
import '../widgets/file_tile.dart';
import '../widgets/message_view.dart';
import '../widgets/open_file.dart';
import '../widgets/quick_actions.dart';

enum _FavSort { starred, name, folder }

/// Every starred file and folder, with a few ways to order them.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key, required this.settings, required this.onOpenFolder});

  final SettingsController settings;
  final void Function(String path) onOpenFolder;

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  _FavSort _sort = _FavSort.starred;
  bool _onlyFolders = false;

  List<FileItem> _items() {
    var items = itemsFromPaths(widget.settings.favoriteFiles);
    if (_onlyFolders) items = items.where((i) => i.isDirectory).toList();
    switch (_sort) {
      case _FavSort.starred:
        break;
      case _FavSort.name:
        items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case _FavSort.folder:
        items.sort((a, b) {
          final c = a.parentPath.toLowerCase().compareTo(b.parentPath.toLowerCase());
          return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        final items = _items();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Favourites'),
            actions: [
              IconButton(
                tooltip: _onlyFolders ? 'Show everything' : 'Folders only',
                icon: Icon(_onlyFolders ? Icons.folder : Icons.folder_outlined),
                onPressed: () => setState(() => _onlyFolders = !_onlyFolders),
              ),
              PopupMenuButton<_FavSort>(
                tooltip: 'Sort',
                icon: const Icon(Icons.sort),
                initialValue: _sort,
                onSelected: (v) => setState(() => _sort = v),
                itemBuilder: (_) => [
                  for (final (v, label) in const [
                    (_FavSort.starred, 'Newest starred'),
                    (_FavSort.name, 'Name'),
                    (_FavSort.folder, 'Folder'),
                  ])
                    CheckedPopupMenuItem<_FavSort>(
                      value: v,
                      checked: _sort == v,
                      child: Text(label),
                    ),
                ],
              ),
            ],
          ),
          body: items.isEmpty
              ? MessageView(
                  icon: Icons.star_outline,
                  title: _onlyFolders ? 'No favourite folders' : 'No favourites yet',
                  body: 'Open the ⋮ menu on a file or folder and tap Favourite.',
                )
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return FileTile(
                      item: item,
                      subtitle: item.parentPath.replaceFirst('/storage/emulated/0', 'Internal storage'),
                      onTap: () {
                        if (item.isDirectory) {
                          Navigator.pop(context);
                          widget.onOpenFolder(item.path);
                        } else {
                          openFile(context, item);
                        }
                      },
                      onMore: () => showQuickActions(context, item),
                    );
                  },
                ),
        );
      },
    );
  }
}
