import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/file_item.dart';
import '../models/storage_category.dart';
import '../services/storage_controller.dart';
import '../services/storage_scanner.dart';
import '../utils/format.dart';
import '../utils/paths.dart';
import '../widgets/delete_file.dart';
import '../widgets/file_details.dart';
import '../widgets/file_tile.dart';
import '../widgets/message_view.dart';
import '../widgets/open_file.dart';

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

  Future<void> _onAction(String action, FileItem item) async {
    switch (action) {
      case 'folder':
        widget.onShowInFolder(item.parentPath);
      case 'details':
        await showFileDetails(context, item);
      case 'share':
        await SharePlus.instance.share(ShareParams(files: [XFile(item.path)]));
      case 'delete':
        final deleted = await deleteFileWithConfirm(context, item);
        if (deleted) {
          widget.controller.forget(item);
          widget.controller.markStale();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
      ),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
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

    final files = _files(scan);
    if (files.isEmpty) {
      return MessageView(
        icon: widget.category.icon,
        title: 'Nothing here',
        body: 'No ${widget.category.label.toLowerCase()} found on your device.',
      );
    }

    final totalBytes = files.fold<int>(0, (sum, f) => sum + f.size);

    return RefreshIndicator(
      onRefresh: c.load,
      child: ListView.builder(
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
          return FileTile(
            item: item,
            subtitle: '${formatBytes(item.size)} · ${folderLabelFor(item.path)}',
            onTap: () => openFile(context, item),
            trailing: PopupMenuButton<String>(
              onSelected: (v) => _onAction(v, item),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'folder', child: Text('Show in folder')),
                PopupMenuItem(value: 'share', child: Text('Share')),
                PopupMenuItem(value: 'details', child: Text('Details')),
                PopupMenuItem(value: 'delete', child: Text('Move to trash')),
              ],
            ),
          );
        },
      ),
    );
  }
}