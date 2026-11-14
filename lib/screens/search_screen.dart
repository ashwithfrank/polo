import 'dart:async';

import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../models/storage_category.dart';
import '../services/storage_controller.dart';
import '../services/storage_scanner.dart';
import '../utils/format.dart';
import '../utils/paths.dart';
import '../widgets/file_tile.dart';
import '../widgets/message_view.dart';
import '../widgets/open_file.dart';

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
      if (mounted) setState(() => _query = value.trim());
    });
    setState(() {}); // keeps the clear button in sync
  }

  void _clear() {
    _debounce?.cancel();
    _text.clear();
    setState(() => _query = '');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
      ),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => _buildBody(context),
      ),
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
              onSelected: (_) => setState(() => _scope = i),
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
                subtitle: item.isDirectory
                    ? folderLabelFor(item.path)
                    : '${formatBytes(item.size)} · ${folderLabelFor(item.path)}',
                onTap: () => item.isDirectory
                    ? widget.onOpenFolder(item.path)
                    : openFile(context, item),
                trailing: item.isDirectory
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