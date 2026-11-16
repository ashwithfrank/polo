import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/storage_access.dart';
import '../utils/format.dart';
import '../utils/paths.dart';
import '../widgets/file_actions.dart';
import '../widgets/file_tile.dart';
import '../widgets/message_view.dart';
import '../widgets/open_file.dart';

/// One way of narrowing the list, such as "Over 100 MB" or "APK files".
class CleanupFilter {
  const CleanupFilter(this.label, this.test);

  final String label;
  final bool Function(FileItem item) test;
}

enum CleanupSort {
  largest('Largest first'),
  oldest('Oldest first'),
  newest('Newest first');

  const CleanupSort(this.label);
  final String label;
}

/// A list of files to review and move to the trash. Nothing is selected for
/// you: you choose what goes. Used by Large files, Old files and the
/// Downloads cleaner.
class CleanupScreen extends StatefulWidget {
  const CleanupScreen({
    super.key,
    required this.title,
    required this.intro,
    required this.loader,
    required this.filters,
    this.initialFilter = 0,
    this.initialSort = CleanupSort.largest,
    this.emptyTitle = 'Nothing found',
    this.emptyBody = 'Try another filter.',
  });

  final String title;
  final String intro;
  final Future<List<FileItem>> Function() loader;
  final List<CleanupFilter> filters;
  final int initialFilter;
  final CleanupSort initialSort;
  final String emptyTitle;
  final String emptyBody;

  @override
  State<CleanupScreen> createState() => _CleanupScreenState();
}

class _CleanupScreenState extends State<CleanupScreen> {
  bool? _granted;
  bool _loading = true;
  String? _error;
  List<FileItem> _all = const [];
  List<int> _counts = const [];

  late int _filter = widget.initialFilter;
  late CleanupSort _sort = widget.initialSort;
  final Set<String> _selected = {};

  List<FileItem>? _visibleCache;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    var ok = await StorageAccess.isGranted();
    if (!ok) ok = await StorageAccess.request();
    if (!mounted) return;
    setState(() => _granted = ok);
    if (ok) await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final files = await widget.loader();
      if (!mounted) return;
      setState(() {
        _all = files;
        _selected.clear();
        _loading = false;
        _recount();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't read your files";
      });
    }
  }

  void _recount() {
    _visibleCache = null;
    _counts = [
      for (final f in widget.filters) _all.where(f.test).length,
    ];
  }

  List<FileItem> get _visible {
    final cached = _visibleCache;
    if (cached != null) return cached;
    final list = _all.where(widget.filters[_filter].test).toList();
    switch (_sort) {
      case CleanupSort.largest:
        list.sort((a, b) => b.size.compareTo(a.size));
      case CleanupSort.oldest:
        list.sort((a, b) => a.modified.compareTo(b.modified));
      case CleanupSort.newest:
        list.sort((a, b) => b.modified.compareTo(a.modified));
    }
    return _visibleCache = list;
  }

  List<FileItem> get _chosen =>
      _all.where((f) => _selected.contains(f.path)).toList();

  void _toggle(FileItem item) {
    setState(() {
      if (!_selected.remove(item.path)) _selected.add(item.path);
    });
  }

  void _toggleAllVisible() {
    final visible = _visible;
    final allSelected = visible.isNotEmpty && visible.every((f) => _selected.contains(f.path));
    setState(() {
      for (final f in visible) {
        allSelected ? _selected.remove(f.path) : _selected.add(f.path);
      }
    });
  }

  void _removed(List<FileItem> gone) {
    if (gone.isEmpty) return;
    final paths = gone.map((f) => f.path).toSet();
    setState(() {
      _all = _all.where((f) => !paths.contains(f.path)).toList();
      _selected.removeAll(paths);
      _recount();
    });
  }

  Future<void> _trash() async {
    final chosen = _chosen;
    if (chosen.isEmpty) return;
    _removed(await trashFiles(context, chosen));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chosen = _selected.isEmpty ? const <FileItem>[] : _chosen;
    final chosenBytes = chosen.fold<int>(0, (sum, f) => sum + f.size);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_granted == true && !_loading && _all.isNotEmpty) ...[
            IconButton(
              tooltip: 'Select all',
              icon: const Icon(Icons.select_all),
              onPressed: _toggleAllVisible,
            ),
            PopupMenuButton<CleanupSort>(
              tooltip: 'Sort',
              icon: const Icon(Icons.sort),
              initialValue: _sort,
              onSelected: (v) => setState(() {
                _sort = v;
                _visibleCache = null;
              }),
              itemBuilder: (_) => [
                for (final s in CleanupSort.values)
                  CheckedPopupMenuItem(
                    value: s,
                    checked: _sort == s,
                    child: Text(s.label),
                  ),
              ],
            ),
          ],
        ],
      ),
      body: _buildBody(context),
      bottomNavigationBar: chosen.isEmpty
          ? null
          : SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: _trash,
            icon: const Icon(Icons.delete_outline),
            label: Text(
              'Move ${chosen.length} to trash · ${formatBytes(chosenBytes)}',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_granted == null || (_loading && _granted == true)) {
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
            Text('Looking through your files…'),
          ],
        ),
      );
    }
    if (_granted == false) {
      return MessageView(
        icon: Icons.folder_special_outlined,
        title: 'Allow access to your files',
        body: 'Polo needs permission to look through your files.',
        actionLabel: 'Grant access',
        onAction: _start,
      );
    }
    if (_error != null) {
      return MessageView(
        icon: Icons.error_outline,
        title: _error!,
        body: 'Try again in a moment.',
        actionLabel: 'Try again',
        onAction: _load,
      );
    }

    final visible = _visible;
    final visibleBytes = visible.fold<int>(0, (sum, f) => sum + f.size);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.intro,
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65), fontSize: 13),
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: widget.filters.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => ChoiceChip(
              label: Text('${widget.filters[i].label} (${_counts[i]})'),
              selected: _filter == i,
              onSelected: (_) => setState(() {
                _filter = i;
                _visibleCache = null;
              }),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${visible.length} ${visible.length == 1 ? 'file' : 'files'} · ${formatBytes(visibleBytes)}',
              style: TextStyle(fontWeight: FontWeight.w600, color: scheme.primary),
            ),
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? MessageView(
            icon: Icons.check_circle_outline,
            title: widget.emptyTitle,
            body: widget.emptyBody,
          )
              : ListView.builder(
            itemCount: visible.length,
            itemBuilder: (context, i) {
              final item = visible[i];
              return FileTile(
                item: item,
                selected: _selected.contains(item.path),
                subtitle:
                '${item.sizeLabel} · ${item.dateLabel} · ${folderLabelFor(item.path)}',
                onTap: () => _toggle(item),
                onLongPress: () => _toggle(item),
                trailing: IconButton(
                  tooltip: 'Open',
                  icon: const Icon(Icons.visibility_outlined),
                  onPressed: () async {
                    final gone = await openFile(context, item);
                    if (mounted) _removed(gone);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}