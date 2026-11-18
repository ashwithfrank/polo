import 'dart:io';

import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/file_service.dart';
import '../widgets/file_tile.dart';
import '../widgets/open_file.dart';
import '../widgets/polo_message.dart';
import '../widgets/progress_dialog.dart';

/// Files another app shared with Polo. Open them, or keep a copy in Downloads.
class ReceivedFilesScreen extends StatefulWidget {
  const ReceivedFilesScreen({super.key, required this.items});

  final List<FileItem> items;

  @override
  State<ReceivedFilesScreen> createState() => _ReceivedFilesScreenState();
}

class _ReceivedFilesScreenState extends State<ReceivedFilesScreen> {
  bool _saved = false;

  static final _folder = '${FileService.rootPath}/Download/Polo received';

  Future<void> _save() async {
    final detail = ValueNotifier<String>('');
    var done = 0;
    String? error;
    try {
      await runWithProgress(
        context,
        'Saving files…',
            () async {
          final files = FileService();
          await Directory(_folder).create(recursive: true);
          for (var i = 0; i < widget.items.length; i++) {
            final item = widget.items[i];
            detail.value = '${i + 1} of ${widget.items.length} · ${item.name}';
            try {
              final target = await files.uniquePath(_folder, item.name);
              await File(item.path).copy(target);
              done++;
            } on FileSystemException catch (e) {
              error = e.osError?.message ?? e.message;
            }
          }
        },
        detail: detail,
      );
    } finally {
      detail.dispose();
    }
    if (!mounted) return;
    setState(() => _saved = done > 0);
    showPoloMessage(
      context,
      error != null && done == 0
          ? "Couldn't save: $error"
          : 'Saved $done ${done == 1 ? 'file' : 'files'} in Download/Polo received',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = widget.items.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Shared with Polo')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              '$count ${count == 1 ? 'file' : 'files'} received. Tap one to open it.',
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
            ),
          ),
          for (final item in widget.items)
            FileTile(item: item, onTap: () => openFile(context, item)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _saved ? null : _save,
            icon: Icon(_saved ? Icons.check : Icons.download_outlined),
            label: Text(_saved ? 'Saved' : 'Save to Downloads'),
          ),
        ),
      ),
    );
  }
}