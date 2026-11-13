import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/file_item.dart';
import '../services/file_service.dart';
import '../widgets/file_tile.dart';

/// A small in-app file picker. Shows folders and the files [accepts] allows,
/// and pops with the list of chosen [FileItem]s.
class PickFilesScreen extends StatefulWidget {
  const PickFilesScreen({super.key, required this.title, required this.accepts});

  final String title;
  final bool Function(FileItem item) accepts;

  @override
  State<PickFilesScreen> createState() => _PickFilesScreenState();
}

class _PickFilesScreenState extends State<PickFilesScreen> with WidgetsBindingObserver {
  final _service = FileService();

  bool? _granted;
  String _path = FileService.rootPath;
  List<FileItem> _items = const [];
  final Map<String, FileItem> _picked = {};
  bool _loading = true;
  String? _error;

  bool get _atRoot => _path == FileService.rootPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init(request: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may have just granted access in system settings.
    if (state == AppLifecycleState.resumed && _granted != true) {
      _init(request: false);
    }
  }

  Future<void> _init({required bool request}) async {
    var ok = await Permission.manageExternalStorage.isGranted ||
        await Permission.storage.isGranted;
    if (!ok && request) {
      var status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) status = await Permission.storage.request();
      ok = status.isGranted;
    }
    if (!mounted) return;
    setState(() => _granted = ok);
    if (ok) await _load(_path);
  }

  Future<void> _load(String path) async {
    setState(() => _loading = true);
    try {
      final all = await _service.list(path, sortBy: SortBy.name, showHidden: false);
      if (!mounted) return;
      setState(() {
        _path = path;
        _items = all.where((i) => i.isDirectory || widget.accepts(i)).toList();
        _error = null;
        _loading = false;
      });
    } on FileSystemException catch (e) {
      if (!mounted) return;
      setState(() {
        _path = path;
        _items = const [];
        _error = e.osError?.message ?? e.message;
        _loading = false;
      });
    }
  }

  void _goUp() {
    if (_atRoot) return;
    _load(Directory(_path).parent.path);
  }

  void _toggle(FileItem item) {
    setState(() {
      if (_picked.remove(item.path) == null) _picked[item.path] = item;
    });
  }

  void _selectAllHere() {
    setState(() {
      for (final item in _items.where((i) => !i.isDirectory)) {
        _picked[item.path] = item;
      }
    });
  }

  String get _pathLabel => _atRoot
      ? 'Internal storage'
      : _path.substring(FileService.rootPath.length + 1);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = _picked.length;

    return PopScope(
      canPop: _atRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goUp();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            if (_granted == true)
              IconButton(
                tooltip: 'Select all in this folder',
                icon: const Icon(Icons.select_all),
                onPressed: _selectAllHere,
              ),
          ],
        ),
        body: _buildBody(context),
        bottomNavigationBar: count == 0
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: scheme.primary,
                    ),
                    onPressed: () => Navigator.pop(context, _picked.values.toList()),
                    child: Text('Continue with $count ${count == 1 ? 'file' : 'files'}'),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_granted == null || (_loading && _granted == true)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_granted == false) {
      return _CenteredMessage(
        icon: Icons.folder_special_outlined,
        title: 'Allow access to your files',
        body: 'Polo needs permission to see your files so you can choose them.',
        actionLabel: 'Grant access',
        onAction: () => _init(request: true),
      );
    }
    if (_error != null) {
      return _CenteredMessage(
        icon: Icons.lock_outline,
        title: "Couldn't open this folder",
        body: _error!,
      );
    }

    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              _pathLabel,
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 13),
            ),
          ),
        ),
        Expanded(
          child: _items.isEmpty
              ? const _CenteredMessage(
                  icon: Icons.folder_open_outlined,
                  title: 'Nothing to choose here',
                  body: 'Open another folder to find files.',
                )
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final item = _items[i];
                    return FileTile(
                      item: item,
                      selected: _picked.containsKey(item.path),
                      onTap: () => item.isDirectory ? _load(item.path) : _toggle(item),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: scheme.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}