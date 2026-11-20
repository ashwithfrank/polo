import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../models/storage_category.dart';
import '../services/storage_controller.dart';
import '../services/storage_scanner.dart';
import '../utils/format.dart';
import '../utils/paths.dart';
import '../widgets/file_actions.dart';
import '../widgets/quick_actions.dart';
import '../widgets/file_details.dart';
import '../widgets/file_tile.dart';
import '../widgets/message_view.dart';
import '../widgets/open_file.dart';
import '../widgets/selection_bar.dart';
import '../widgets/haptics.dart';
import '../widgets/drag_select.dart';

enum _Sort { date, size, name }

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({
    super.key,
    required this.controller,
    required this.category,
    required this.onShowInFolder,
  });

  final StorageController controller;
  final StorageCategory category;
  final void Function(String folderPath) onShowInFolder;

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  _Sort _sort = _Sort.date;
  final Set<String> _selected = {};
  final _scroll = ScrollController();

  bool get _selecting => _selected.isNotEmpty;

  List<FileItem> _files(ScanResult scan) {
    final list = scan.index
        .where((i) => !i.isDirectory && StorageCategory.of(i.kind) == widget.category)
        .toList();

    int Function(FileItem, FileItem) compare;
    switch (_sort) {
      case _Sort.date:
        compare = (a, b) => b.modified.compareTo(a.modified);
      case _Sort.size:
        compare = (a, b) => b.size.compareTo(a.size);
      case _Sort.name:
        compare = (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }
    list.sort(compare);
    return list;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toggle(FileItem item) {
    Haptics.select();
    setState(() {
      if (!_selected.remove(item.path)) _selected.add(item.path);
    });
  }

  List<FileItem> _selectedFrom(List<FileItem> files) =>
      files.where((f) => _selected.contains(f.path)).toList();

  /// Forgets files that were moved to the trash.
  void _removed(List<FileItem> moved) {
    for (final f in moved) {
      widget.controller.forget(f);
    }
    if (moved.isNotEmpty) widget.controller.markStale();
    setState(() => _selected.removeAll(moved.map((f) => f.path)));
  }

  /// Something changed on disk (a new zip, new names): rescan.
  void _changed() {
    setState(_selected.clear);
    widget.controller.markStale();
    widget.controller.load();
  }

  Future<void> _onAction(String action, FileItem item) async {
    switch (action) {
      case 'quick':
        if (await showQuickActions(context, item) && mounted) _changed();
      case 'folder':
        widget.onShowInFolder(item.parentPath);
      case 'details':
        await showFileDetails(context, item);
      case 'share':
        await shareFiles(context, [item]);
      case 'delete':
        _removed(await trashFiles(context, [item]));
    }
  }

  PreferredSizeWidget _buildAppBar(List<FileItem> files) {
    if (_selecting) {
      return AppBar(
        leading: IconButton(
          tooltip: 'Cancel selection',
          icon: const Icon(Icons.close),
          onPressed: () => setState(_selected.clear),
        ),
        title: Text('${_selected.length} selected'),
        actions: [
          IconButton(
            tooltip: 'Select all',
            icon: const Icon(Icons.select_all),
            onPressed: () => setState(() => _selected.addAll(files.map((f) => f.path))),
          ),
        ],
      );
    }
    return AppBar(
      title: Text(widget.category.label),
      actions: [
        PopupMenuButton<_Sort>(
          tooltip: 'Sort',
          icon: const Icon(Icons.sort),
          initialValue: _sort,
          onSelected: (v) => setState(() => _sort = v),
          itemBuilder: (_) => [
            CheckedPopupMenuItem(
              value: _Sort.date,
              checked: _sort == _Sort.date,
              child: const Text('Newest first'),
            ),
            CheckedPopupMenuItem(
              value: _Sort.size,
              checked: _sort == _Sort.size,
              child: const Text('Largest first'),
            ),
            CheckedPopupMenuItem(
              value: _Sort.name,
              checked: _sort == _Sort.name,
              child: const Text('Name'),
            ),
          ],
        ),
      ],
    );
  }

  Widget? _buildSelectionBar(List<FileItem> files) {
    if (!_selecting) return null;
    final chosen = _selectedFrom(files);
    if (chosen.isEmpty) return null;
    final scheme = Theme.of(context).colorScheme;

    return SelectionActionBar(
      actions: [
        SelectionAction(
          icon: Icons.share_outlined,
          label: 'Share',
          onTap: () => shareFiles(context, chosen),
        ),
        SelectionAction(
          icon: Icons.folder_zip_outlined,
          label: 'Zip',
          onTap: () async {
            if (await zipFiles(context, chosen)) _changed();
          },
        ),
        SelectionAction(
          icon: Icons.drive_file_rename_outline,
          label: 'Rename',
          onTap: () async {
            if (await renameFiles(context, chosen)) _changed();
          },
        ),
        if (chosen.length == 1)
          SelectionAction(
            icon: Icons.info_outline,
            label: 'Details',
            onTap: () => showFileDetails(context, chosen.first),
          ),
        SelectionAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          color: scheme.error,
          onTap: () async => _removed(await trashFiles(context, chosen)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final scan = widget.controller.scan;
        final files = scan == null ? const <FileItem>[] : _files(scan);
        return PopScope(
          canPop: !_selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(_selected.clear);
          },
          child: Scaffold(
            appBar: _buildAppBar(files),
            body: _buildBody(context, files),
            bottomNavigationBar: _buildSelectionBar(files),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, List<FileItem> files) {
    final c = widget.controller;
    final scheme = Theme.of(context).colorScheme;

    if (c.needsAccess) {
      return MessageView(
        icon: Icons.folder_special_outlined,
        title: 'Allow access to your files',
        body: 'Polo needs permission to see your files.',
        actionLabel: 'Grant access',
        onAction: c.requestAccess,
      );
    }

    final scan = c.scan;
    if (scan == null) {
      return c.loading
          ? const Center(child: CircularProgressIndicator())
          : MessageView(
              icon: Icons.error_outline,
              title: "Couldn't load your files",
              body: c.error ?? 'Try again in a moment.',
              actionLabel: 'Try again',
              onAction: c.load,
            );
    }

    if (files.isEmpty) {
      return MessageView(
        icon: widget.category.icon,
        title: 'Nothing here',
        body: 'No ${widget.category.label.toLowerCase()} found on your device.',
      );
    }

    final totalBytes = files.fold<int>(0, (sum, f) => sum + f.size);

    return DragSelectArea(
      order: [for (final f in files) f.path],
      selected: _selected,
      scroll: _scroll,
      onChanged: (next) => setState(() {
        _selected
          ..clear()
          ..addAll(next);
      }),
      child: RefreshIndicator(
      onRefresh: c.load,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: files.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                '${files.length} ${files.length == 1 ? 'file' : 'files'} · ${formatBytes(totalBytes)}',
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
              ),
            );
          }
          final item = files[i - 1];
          return DragSelectItem(path: item.path, child: FileTile(
            item: item,
            subtitle: '${formatBytes(item.size)} · ${folderLabelFor(item.path)}',
            selected: _selected.contains(item.path),
            onTap: () async {
              if (_selecting) {
                _toggle(item);
                return;
              }
              final deleted = await openFile(context, item);
              for (final f in deleted) {
                widget.controller.forget(f);
              }
            },
            trailing: _selecting
                ? null
                : PopupMenuButton<String>(
              onSelected: (v) => _onAction(v, item),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'quick', child: Text('Quick actions')),
                PopupMenuItem(value: 'folder', child: Text('Show in folder')),
                PopupMenuItem(value: 'share', child: Text('Share')),
                PopupMenuItem(value: 'details', child: Text('Details')),
                PopupMenuItem(value: 'delete', child: Text('Move to trash')),
              ],
            ),
          ));
        },
      ),
      ),
    );
  }
}
