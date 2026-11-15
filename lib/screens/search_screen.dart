import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/file_item.dart';
import '../models/storage_category.dart';
import '../services/storage_controller.dart';
import '../services/storage_scanner.dart';
import '../utils/format.dart';
import '../utils/paths.dart';
import '../widgets/file_actions.dart';
import '../widgets/file_details.dart';
import '../widgets/file_tile.dart';
import '../widgets/message_view.dart';
import '../widgets/open_file.dart';
import '../widgets/selection_bar.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.controller,
    required this.onOpenFolder,
  });

  final StorageController controller;
  final void Function(String path) onOpenFolder;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _text = TextEditingController();
  Timer? _debounce;
  String _query = '';
  int _scope = 0;

  List<FileItem> _cached = const [];
  ScanResult? _cachedScan;
  String _cachedKey = '';

  final Set<String> _selected = {};
  bool get _selecting => _selected.isNotEmpty;

  void _toggle(FileItem item) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.remove(item.path)) _selected.add(item.path);
    });
  }

  List<FileItem> _chosen() =>
      _cached.where((f) => _selected.contains(f.path)).toList();

  void _removed(List<FileItem> moved) {
    for (final f in moved) {
      widget.controller.forget(f);
    }
    if (moved.isNotEmpty) widget.controller.markStale();
    setState(() {
      _selected.removeAll(moved.map((f) => f.path));
      _cachedKey = ''; // results must be rebuilt without the removed files
    });
  }

  void _changed() {
    setState(() {
      _selected.clear();
      _cachedKey = '';
    });
    widget.controller.markStale();
    widget.controller.load();
  }

  static final _scopes = [
    (label: 'All', test: (FileItem i) => true),
    (label: 'Folders', test: (FileItem i) => i.isDirectory),
    for (final c in StorageCategory.values.where((c) => c != StorageCategory.other))
      (
      label: c.label,
      test: (FileItem i) => !i.isDirectory && StorageCategory.of(i.kind) == c,
      ),
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) {
        setState(() {
          _query = value.trim();
          _selected.clear();
        });
      }
    });
    setState(() {}); // keeps the clear button in sync
  }

  void _clear() {
    _debounce?.cancel();
    _text.clear();
    setState(() {
      _query = '';
      _selected.clear();
    });
  }

  List<FileItem> _resultsFor(ScanResult scan) {
    final key = '$_query|$_scope';
    if (identical(scan, _cachedScan) && key == _cachedKey) return _cached;

    final words = _query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    var results = <FileItem>[];
    if (words.isNotEmpty) {
      final test = _scopes[_scope].test;
      final starts = <FileItem>[];
      final others = <FileItem>[];
      for (final item in scan.index) {
        if (!test(item)) continue;
        final name = item.name.toLowerCase();
        if (!words.every((w) => name.contains(w))) continue;
        (name.startsWith(words.first) ? starts : others).add(item);
        if (starts.length + others.length >= 2000) break;
      }
      int newestFirst(FileItem a, FileItem b) => b.modified.compareTo(a.modified);
      starts.sort(newestFirst);
      others.sort(newestFirst);
      results = [...starts, ...others].take(200).toList();
    }

    _cachedScan = scan;
    _cachedKey = key;
    _cached = results;
    return results;
  }

  PreferredSizeWidget _buildAppBar() {
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
            onPressed: () => setState(() => _selected.addAll(_cached.map((f) => f.path))),
          ),
        ],
      );
    }
    return AppBar(
      titleSpacing: 0,
      title: TextField(
        controller: _text,
        autofocus: true,
        textInputAction: TextInputAction.search,
        onChanged: _onChanged,
        decoration: const InputDecoration(
          hintText: 'Search files and folders',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
      actions: [
        if (_text.text.isNotEmpty)
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.close),
            onPressed: _clear,
          ),
      ],
    );
  }

  Widget? _buildSelectionBar() {
    final chosen = _chosen();
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
        final body = _buildBody(context);
        return PopScope(
          canPop: !_selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(_selected.clear);
          },
          child: Scaffold(
            appBar: _buildAppBar(),
            body: body,
            bottomNavigationBar: _buildSelectionBar(),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    final c = widget.controller;

    if (c.needsAccess) {
      return MessageView(
        icon: Icons.folder_special_outlined,
        title: 'Allow access to your files',
        body: 'Polo needs permission to see your files so you can search them.',
        actionLabel: 'Grant access',
        onAction: c.requestAccess,
      );
    }

    final scan = c.scan;
    if (scan == null) {
      if (c.loading) {
        return const Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Indexing your files…'),
            ],
          ),
        );
      }
      return MessageView(
        icon: Icons.search_off,
        title: "Couldn't load your files",
        body: c.error ?? 'Try again in a moment.',
        actionLabel: 'Try again',
        onAction: c.load,
      );
    }

    final results = _resultsFor(scan);

    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _scopes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => ChoiceChip(
              label: Text(_scopes[i].label),
              selected: _scope == i,
              onSelected: (_) => setState(() {
                _scope = i;
                _selected.clear();
              }),
            ),
          ),
        ),
        Expanded(
          child: results.isEmpty
              ? (_query.isEmpty
              ? const MessageView(
            icon: Icons.search,
            title: 'Search your files',
            body: 'Type a name to find files and folders.',
          )
              : MessageView(
            icon: Icons.search_off,
            title: 'No results',
            body: 'Nothing matches "$_query".',
          ))
              : ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, i) {
              final item = results[i];
              return FileTile(
                item: item,
                selected: _selected.contains(item.path),
                onLongPress: () => _toggle(item),
                subtitle: item.isDirectory
                    ? folderLabelFor(item.path)
                    : '${formatBytes(item.size)} · ${folderLabelFor(item.path)}',
                onTap: () {
                  if (_selecting) {
                    _toggle(item);
                  } else if (item.isDirectory) {
                    widget.onOpenFolder(item.path);
                  } else {
                    openFile(context, item);
                  }
                },
                trailing: item.isDirectory || _selecting
                    ? null
                    : IconButton(
                  tooltip: 'Show in folder',
                  icon: const Icon(Icons.folder_open_outlined),
                  onPressed: () => widget.onOpenFolder(item.parentPath),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}