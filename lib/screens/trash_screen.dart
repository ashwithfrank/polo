import 'dart:io';

import 'package:flutter/material.dart';

import '../services/trash_service.dart';
import '../utils/format.dart';
import '../utils/paths.dart';
import '../widgets/file_details.dart';
import '../widgets/file_tile.dart';
import '../widgets/message_view.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final _trash = TrashService();

  List<TrashEntry>? _entries;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await _trash.list();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _error = null;
      });
    } on FileSystemException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.osError?.message ?? e.message);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true && mounted;
  }

  Future<void> _restore(TrashEntry entry) async {
    try {
      final path = await _trash.restore(entry);
      if (mounted) _toast('Restored to ${folderLabelFor(path)}');
    } on FileSystemException catch (e) {
      if (mounted) _toast(e.osError?.message ?? e.message);
    }
    await _load();
  }

  Future<void> _deleteForever(TrashEntry entry) async {
    if (!await _confirm(
      'Delete forever?',
      "${entry.name} will be deleted. This can't be undone.",
      'Delete',
    )) {
      return;
    }
    try {
      await _trash.deleteForever(entry);
    } on FileSystemException catch (e) {
      if (mounted) _toast(e.osError?.message ?? e.message);
    }
    await _load();
  }

  Future<void> _empty() async {
    if (!await _confirm(
      'Empty trash?',
      "Everything in the trash will be deleted. This can't be undone.",
      'Empty trash',
    )) {
      return;
    }
    try {
      await _trash.empty();
    } on FileSystemException catch (e) {
      if (mounted) _toast(e.osError?.message ?? e.message);
    }
    await _load();
  }

  String _ago(DateTime t) {
    final days = DateTime.now().difference(t).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    return '$days days ago';
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        actions: [
          if (entries != null && entries.isNotEmpty)
            IconButton(
              tooltip: 'Empty trash',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _empty,
            ),
        ],
      ),
      body: Builder(builder: (context) {
        if (_error != null) {
          return MessageView(
            icon: Icons.lock_outline,
            title: "Couldn't open the trash",
            body: _error!,
          );
        }
        if (entries == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (entries.isEmpty) {
          return const MessageView(
            icon: Icons.delete_outline,
            title: 'Trash is empty',
            body: 'Deleted files show up here for 30 days.',
          );
        }
        return ListView.builder(
          itemCount: entries.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Items are deleted for good after ${TrashService.retentionDays} days.',
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
                ),
              );
            }
            final e = entries[i - 1];
            final size = e.isDirectory ? 'Folder' : formatBytes(e.size);
            return FileTile(
              item: _trash.asFileItem(e),
              subtitle: '$size · ${_ago(e.deletedAt)} · ${folderLabelFor(e.originalPath)}',
              onTap: () => showFileDetails(
                context,
                _trash.asFileItem(e),
                originalPath: e.originalPath,
                deletedAt: e.deletedAt,
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (v) => v == 'restore' ? _restore(e) : _deleteForever(e),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'restore', child: Text('Restore')),
                  PopupMenuItem(value: 'delete', child: Text('Delete forever')),
                ],
              ),
            );
          },
        );
      }),
    );
  }
}