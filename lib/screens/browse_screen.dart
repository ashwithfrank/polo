import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../models/file_item.dart';
import '../services/file_service.dart';
import '../widgets/file_tile.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, required this.active});

  /// True while this tab is the visible one. Used so the system back button
  /// only walks up folders when Browse is on screen.
  final bool active;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> with WidgetsBindingObserver {
  final _service = FileService();
  final _crumbScroll = ScrollController();

  bool? _granted;
  String _path = FileService.rootPath;
  List<FileItem> _items = const [];
  bool _loading = false;
  String? _error;
  SortBy _sortBy = SortBy.name;
  bool _showHidden = false;

  final Set<String> _selected = {};
  List<FileItem> _clipboard = const [];
  bool _clipboardIsMove = false;

  bool get _atRoot => _path == FileService.rootPath;
  bool get _selecting => _selected.isNotEmpty;
  List<FileItem> get _selectedItems =>
      _items.where((i) => _selected.contains(i.path)).toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _crumbScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may have just granted access in system settings.
    if (state == AppLifecycleState.resumed && _granted != true) {
      _checkPermission();
    }
  }

  // ---------------------------------------------------------------------------
  // Permission and loading
  // ---------------------------------------------------------------------------

  Future<bool> _hasAccess() async {
    if (await Permission.manageExternalStorage.isGranted) return true;
    return Permission.storage.isGranted;
  }

  Future<void> _checkPermission() async {
    final ok = await _hasAccess();
    if (!mounted) return;
    final wasGranted = _granted == true;
    setState(() => _granted = ok);
    if (ok && !wasGranted) await _load(_path);
  }

  Future<void> _requestPermission() async {
    var status = await Permission.manageExternalStorage.request();
    if (!status.isGranted) status = await Permission.storage.request();
    await _checkPermission();
  }

  Future<void> _load(String path, {bool showSpinner = true}) async {
    if (showSpinner) setState(() => _loading = true);
    try {
      final items = await _service.list(path, sortBy: _sortBy, showHidden: _showHidden);
      if (!mounted) return;
      final keep = items.map((i) => i.path).toSet();
      setState(() {
        _path = path;
        _items = items;
        _selected.removeWhere((p) => !keep.contains(p));
        _error = null;
        _loading = false;
      });
    } on FileSystemException catch (e) {
      if (!mounted) return;
      setState(() {
        _path = path;
        _items = const [];
        _selected.clear();
        _error = e.osError?.message ?? e.message;
        _loading = false;
      });
    }
    _scrollCrumbsToEnd();
  }

  void _goUp() {
    if (_atRoot) return;
    _load(Directory(_path).parent.path);
  }

  void _scrollCrumbsToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_crumbScroll.hasClients) {
        _crumbScroll.jumpTo(_crumbScroll.position.maxScrollExtent);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Selection and opening
  // ---------------------------------------------------------------------------

  void _toggle(FileItem item) {
    setState(() {
      if (!_selected.remove(item.path)) _selected.add(item.path);
    });
  }

  Future<void> _onTap(FileItem item) async {
    if (_selecting) {
      _toggle(item);
      return;
    }
    if (item.isDirectory) {
      await _load(item.path);
      return;
    }
    final result = await OpenFilex.open(item.path);
    if (result.type != ResultType.done && mounted) {
      _toast(result.type == ResultType.noAppToOpen
          ? 'No app can open this file'
          : result.message);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _count(int n) => n == 1 ? '1 item' : '$n items';

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _stageClipboard({required bool move}) {
    final items = _selectedItems;
    if (items.isEmpty) return;
    setState(() {
      _clipboard = items;
      _clipboardIsMove = move;
      _selected.clear();
    });
    _toast('${_count(items.length)} ready. Open a folder and tap Paste here');
  }

  void _clearClipboard() {
    setState(() => _clipboard = const []);
  }

  Future<void> _paste() async {
    final items = _clipboard;
    final move = _clipboardIsMove;
    setState(() => _loading = true);

    var done = 0;
    String? error;
    for (final item in items) {
      try {
        if (move) {
          await _service.move(item, _path);
        } else {
          await _service.copy(item, _path);
        }
        done++;
      } on FileSystemException catch (e) {
        error = e.osError?.message ?? e.message;
      }
    }

    if (move) _clipboard = const [];
    await _load(_path);
    if (!mounted) return;
    _toast(error ??
        '${move ? 'Moved' : 'Copied'} ${_count(done)}');
  }

  Future<void> _share() async {
    final files = _selectedItems.where((i) => !i.isDirectory).toList();
    if (files.isEmpty) {
      _toast("Folders can't be shared. Select files instead");
      return;
    }
    await SharePlus.instance.share(
      ShareParams(files: [for (final f in files) XFile(f.path)]),
    );
  }

  Future<void> _rename() async {
    final items = _selectedItems;
    if (items.length != 1) return;
    final item = items.first;

    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: 'Rename',
        confirmLabel: 'Rename',
        initial: item.name,
        existing: _items.where((i) => i.path != item.path).map((i) => i.name).toSet(),
      ),
    );
    if (name == null || name == item.name) return;

    try {
      await _service.rename(item, name);
      setState(() => _selected.clear());
      await _load(_path, showSpinner: false);
    } on FileSystemException catch (e) {
      if (mounted) _toast(e.osError?.message ?? e.message);
    }
  }

  Future<void> _delete() async {
    final items = _selectedItems;
    if (items.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${_count(items.length)}?'),
        content: const Text("This can't be undone."),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _loading = true);
    var done = 0;
    String? error;
    for (final item in items) {
      try {
        await _service.delete(item);
        done++;
      } on FileSystemException catch (e) {
        error = e.osError?.message ?? e.message;
      }
    }
    setState(() => _selected.clear());
    await _load(_path);
    if (!mounted) return;
    _toast(error ?? 'Deleted ${_count(done)}');
  }

  Future<void> _newFolder() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: 'New folder',
        confirmLabel: 'Create',
        hint: 'Folder name',
        existing: _items.map((i) => i.name).toSet(),
      ),
    );
    if (name == null) return;

    try {
      await _service.createFolder(_path, name);
      await _load(_path, showSpinner: false);
    } on FileSystemException catch (e) {
      if (mounted) _toast(e.osError?.message ?? e.message);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  List<({String label, String path})> _crumbs() {
    final crumbs = <({String label, String path})>[
      (label: 'Internal storage', path: FileService.rootPath),
    ];
    var current = FileService.rootPath;
    final relative = _path.substring(FileService.rootPath.length);
    for (final part in relative.split('/').where((s) => s.isNotEmpty)) {
      current = '$current/$part';
      crumbs.add((label: part, path: current));
    }
    return crumbs;
  }

  @override
  Widget build(BuildContext context) {
    if (_granted == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_granted == false) {
      return _PermissionPrompt(onGrant: _requestPermission);
    }

    return PopScope(
      canPop: !widget.active || (_atRoot && !_selecting),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selecting) {
          setState(_selected.clear);
        } else {
          _goUp();
        }
      },
      child: Column(
        children: [
          _selecting ? _buildSelectionBar(context) : _buildToolbar(context),
          Expanded(child: _buildBody(context)),
          if (_selecting)
            _buildActionBar(context)
          else if (_clipboard.isNotEmpty)
            _buildPasteBar(context),
        ],
      ),
    );
  }

  Widget _buildSelectionBar(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Cancel selection',
          icon: const Icon(Icons.close),
          onPressed: () => setState(_selected.clear),
        ),
        Expanded(
          child: Text(
            '${_selected.length} selected',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          tooltip: 'Select all',
          icon: const Icon(Icons.select_all),
          onPressed: () => setState(() {
            _selected
              ..clear()
              ..addAll(_items.map((i) => i.path));
          }),
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final crumbs = _crumbs();

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _crumbScroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (var i = 0; i < crumbs.length; i++) ...[
                  if (i > 0)
                    Icon(Icons.chevron_right, size: 18, color: scheme.onSurface.withValues(alpha: 0.5)),
                  _Crumb(
                    label: crumbs[i].label,
                    isLast: i == crumbs.length - 1,
                    onTap: () => _load(crumbs[i].path),
                  ),
                ],
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: 'New folder',
          icon: const Icon(Icons.create_new_folder_outlined),
          onPressed: _newFolder,
        ),
        IconButton(
          tooltip: _showHidden ? 'Hide hidden files' : 'Show hidden files',
          icon: Icon(_showHidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () {
            setState(() => _showHidden = !_showHidden);
            _load(_path);
          },
        ),
        PopupMenuButton<SortBy>(
          tooltip: 'Sort',
          icon: const Icon(Icons.sort),
          initialValue: _sortBy,
          onSelected: (value) {
            setState(() => _sortBy = value);
            _load(_path);
          },
          itemBuilder: (_) => [
            CheckedPopupMenuItem(
              value: SortBy.name,
              checked: _sortBy == SortBy.name,
              child: const Text('Name'),
            ),
            CheckedPopupMenuItem(
              value: SortBy.date,
              checked: _sortBy == SortBy.date,
              child: const Text('Date modified'),
            ),
            CheckedPopupMenuItem(
              value: SortBy.size,
              checked: _sortBy == SortBy.size,
              child: const Text('Size'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _Message(
        icon: Icons.lock_outline,
        title: "Couldn't open this folder",
        body: _error!,
        actionLabel: 'Try again',
        onAction: () => _load(_path),
      );
    }
    if (_items.isEmpty) {
      return const _Message(
        icon: Icons.folder_open_outlined,
        title: 'This folder is empty',
        body: 'Files you add here will show up in this list.',
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(_path, showSpinner: false),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final item = _items[i];
          return FileTile(
            item: item,
            selected: _selected.contains(item.path),
            onTap: () => _onTap(item),
            onLongPress: () => _toggle(item),
          );
        },
      ),
    );
  }

  Widget _buildActionBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            _ActionButton(
              icon: Icons.copy_outlined,
              label: 'Copy',
              onTap: () => _stageClipboard(move: false),
            ),
            _ActionButton(
              icon: Icons.drive_file_move_outlined,
              label: 'Move',
              onTap: () => _stageClipboard(move: true),
            ),
            _ActionButton(icon: Icons.share_outlined, label: 'Share', onTap: _share),
            if (_selected.length == 1)
              _ActionButton(
                icon: Icons.drive_file_rename_outline,
                label: 'Rename',
                onTap: _rename,
              ),
            _ActionButton(
              icon: Icons.delete_outline,
              label: 'Delete',
              color: scheme.error,
              onTap: _delete,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasteBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${_count(_clipboard.length)} to ${_clipboardIsMove ? 'move' : 'copy'}',
                style: TextStyle(color: scheme.onPrimaryContainer),
              ),
            ),
            TextButton(onPressed: _clearClipboard, child: const Text('Cancel')),
            const SizedBox(width: 4),
            FilledButton(onPressed: _paste, child: const Text('Paste here')),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? Theme.of(context).colorScheme.onSurface;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: fg),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 11, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.confirmLabel,
    required this.existing,
    this.initial = '',
    this.hint,
  });

  final String title;
  final String confirmLabel;
  final String initial;
  final String? hint;
  final Set<String> existing;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    // Pre-select the name without its extension so renaming keeps ".jpg" etc.
    final dot = widget.initial.lastIndexOf('.');
    final end = dot > 0 ? dot : widget.initial.length;
    _controller.selection = TextSelection(baseOffset: 0, extentOffset: end);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    String? error;
    if (name.isEmpty) {
      error = 'Enter a name';
    } else if (name.contains('/')) {
      error = "Names can't contain /";
    } else if (widget.existing.contains(name)) {
      error = "That name's already taken";
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hint, errorText: _error),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({required this.label, required this.isLast, required this.onTap});

  final String label;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: isLast ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
            color: isLast ? scheme.onSurface : scheme.primary,
          ),
        ),
      ),
    );
  }
}

class _PermissionPrompt extends StatelessWidget {
  const _PermissionPrompt({required this.onGrant});

  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    return _Message(
      icon: Icons.folder_special_outlined,
      title: 'Allow access to your files',
      body: 'Polo needs permission to see the files on your device so you can browse them.',
      actionLabel: 'Grant access',
      onAction: onGrant,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
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