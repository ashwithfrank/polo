import 'dart:io';

import 'package:flutter/material.dart';

import '../services/duplicate_finder.dart';
import '../services/storage_access.dart';
import '../services/trash_service.dart';
import '../utils/format.dart';
import '../utils/paths.dart';
import '../widgets/file_tile.dart';
import '../widgets/message_view.dart';
import '../widgets/open_file.dart';
import '../widgets/progress_dialog.dart';

class DuplicatesScreen extends StatefulWidget {
  const DuplicatesScreen({super.key});

  @override
  State<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends State<DuplicatesScreen> {
  bool? _granted;
  bool _scanning = true;
  List<DuplicateGroup> _groups = const [];
  final Set<String> _selected = {};

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
    if (ok) await _scan();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final groups = await DuplicateFinder.scan();
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _scanning = false;
      // Keep the oldest copy of each file, pre-select the rest.
      _selected
        ..clear()
        ..addAll([
          for (final g in groups) ...g.files.skip(1).map((f) => f.path),
        ]);
    });
  }

  int get _selectedBytes {
    var total = 0;
    for (final g in _groups) {
      for (final f in g.files) {
        if (_selected.contains(f.path)) total += f.size;
      }
    }
    return total;
  }

  void _toggle(DuplicateGroup group, String path) {
    final selectedInGroup = group.files.where((f) => _selected.contains(f.path)).length;
    final isSelected = _selected.contains(path);
    if (!isSelected && selectedInGroup == group.files.length - 1) {
      _toast('Keep at least one copy');
      return;
    }
    setState(() => isSelected ? _selected.remove(path) : _selected.add(path));
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _trashSelected() async {
    final count = _selected.length;
    final bytes = _selectedBytes;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Move $count ${count == 1 ? 'file' : 'files'} to trash?'),
        content: Text(
          'This frees ${formatBytes(bytes)}. You can restore them from Trash for ${TrashService.retentionDays} days.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Move to trash'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final targets = [
      for (final g in _groups)
        for (final f in g.files)
          if (_selected.contains(f.path)) f,
    ];
    final trash = TrashService();
    final trashed = <String>{};
    var failed = 0;
    await runWithProgress(context, 'Moving to trash…', () async {
      for (final f in targets) {
        try {
          await trash.moveToTrash(f);
          trashed.add(f.path);
        } on FileSystemException {
          failed++;
        }
      }
    });
    if (!mounted) return;

    // Drop what was removed; hide groups that no longer have duplicates.
    final remaining = <DuplicateGroup>[];
    for (final g in _groups) {
      final left = g.files.where((f) => !trashed.contains(f.path)).toList();
      if (left.length >= 2) remaining.add(DuplicateGroup(left));
    }
    setState(() {
      _groups = remaining;
      _selected.clear();
    });
    _toast(failed == 0
        ? 'Moved ${trashed.length} to trash'
        : 'Moved ${trashed.length} to trash, $failed failed');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wasted = _groups.fold<int>(0, (a, g) => a + g.wastedBytes);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Duplicate finder'),
        actions: [
          if (_granted == true && !_scanning)
            IconButton(
              tooltip: 'Scan again',
              icon: const Icon(Icons.refresh),
              onPressed: _scan,
            ),
        ],
      ),
      body: Builder(builder: (context) {
        if (_granted == false) {
          return MessageView(
            icon: Icons.folder_special_outlined,
            title: 'Allow access to your files',
            body: 'Polo needs permission to look for duplicates.',
            actionLabel: 'Grant access',
            onAction: _start,
          );
        }
        if (_granted == null || _scanning) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Looking for duplicates…'),
                SizedBox(height: 4),
                Text('This can take a minute on a full phone.'),
              ],
            ),
          );
        }
        if (_groups.isEmpty) {
          return const MessageView(
            icon: Icons.check_circle_outline,
            title: 'No duplicates found',
            body: 'Files under 10 KB are ignored.',
          );
        }

        return ListView.builder(
          itemCount: _groups.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  '${_groups.length} ${_groups.length == 1 ? 'set' : 'sets'} of duplicates · ${formatBytes(wasted)} can be freed. The oldest copy is kept.',
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
                ),
              );
            }
            final g = _groups[i - 1];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    '${g.files.length} copies · ${formatBytes(g.size)} each',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (final f in g.files)
                  FileTile(
                    item: f,
                    subtitle: folderLabelFor(f.path),
                    onTap: () => openFile(context, f),
                    onLongPress: () => _toggle(g, f.path),
                    trailing: Checkbox(
                      value: _selected.contains(f.path),
                      onChanged: (_) => _toggle(g, f.path),
                    ),
                  ),
              ],
            );
          },
        );
      }),
      bottomNavigationBar: _selected.isEmpty || _scanning
          ? null
          : SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _trashSelected,
            icon: const Icon(Icons.delete_outline),
            label: Text(
              'Move ${_selected.length} to trash · ${formatBytes(_selectedBytes)}',
            ),
          ),
        ),
      ),
    );
  }
}