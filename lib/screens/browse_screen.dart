import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../models/file_item.dart';
import '../services/archive_service.dart';
import '../services/convert_service.dart';
import '../services/settings_controller.dart';
import '../services/file_service.dart';
import '../services/trash_service.dart';
import '../widgets/file_details.dart';
import '../widgets/file_grid_tile.dart';
import '../widgets/file_tile.dart';
import '../widgets/name_dialog.dart';
import 'convert_images_screen.dart';
import 'images_to_pdf_screen.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({
    super.key,
    required this.active,
    required this.settings,
    this.jumpTo,
  });

  /// True while this tab is the visible one. Used so the system back button
  /// only walks up folders when Browse is on screen.
  final bool active;

  /// Set a folder path on this notifier to make Browse open that folder.
  final ValueNotifier<String?>? jumpTo;

  /// Sort order and hidden-files choice, saved between launches.
  final SettingsController settings;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> with WidgetsBindingObserver {
  final _service = FileService();
  late final _archive = ArchiveService(_service);
  final _crumbScroll = ScrollController();

  bool? _granted;
  String _path = FileService.rootPath;
  List<FileItem> _items = const [];
  bool _loading = false;
  String? _error;
  SortBy get _sortBy => widget.settings.sortBy;
  bool get _showHidden => widget.settings.showHidden;
  late SortBy _lastSort = _sortBy;
  late bool _lastHidden = _showHidden;

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
    widget.jumpTo?.addListener(_onJump);
    widget.settings.addListener(_onSettings);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.jumpTo?.removeListener(_onJump);
    widget.settings.removeListener(_onSettings);
    _crumbScroll.dispose();
    super.dispose();
  }

  void _onSettings() {
    // Sort order or hidden-files choice changed, here or in Settings.
    final changed = _lastSort != _sortBy || _lastHidden != _showHidden;
    _lastSort = _sortBy;
    _lastHidden = _showHidden;
    if (changed && _granted == true) {
      _load(_path, showSpinner: false);
    } else if (mounted) {
      setState(() {}); // e.g. list/grid switch
    }
  }

  void _onJump() {
    final path = widget.jumpTo?.value;
    if (path == null) return;
    widget.jumpTo!.value = null;

    if (_granted != true) {
      // Opened once access has been granted.
      _path = path;
      return;
    }
    if (!Directory(path).existsSync()) {
      _toast("That folder doesn't exist on this device");
      return;
    }
    _selected.clear();
    _path = path;
    _load(path);
  }

  @override
  void didUpdateWidget(BrowseScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pick up files created elsewhere, for example by a conversion in Tools.
    if (widget.active && !oldWidget.active && _granted == true) {
      _load(_path, showSpinner: false);
    }
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
    if (item.extension == 'zip') {
      await _zipTapMenu(item);
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

  Future<void> _more() async {
    final items = _selectedItems;
    if (items.isEmpty) return;
    final single = items.length == 1;
    final allImages = items.every(ConvertService.canConvert);
    final isZip = single && !items.first.isDirectory && items.first.extension == 'zip';

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (single)
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Details'),
                onTap: () => Navigator.pop(context, 'details'),
              ),
            if (single)
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('Rename'),
                onTap: () => Navigator.pop(context, 'rename'),
              ),
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: const Text('Compress to ZIP'),
              onTap: () => Navigator.pop(context, 'zip'),
            ),
            if (isZip)
              ListTile(
                leading: const Icon(Icons.unarchive_outlined),
                title: const Text('Extract here'),
                onTap: () => Navigator.pop(context, 'unzip'),
              ),
            if (allImages) ...[
              ListTile(
                leading: const Icon(Icons.transform),
                title: const Text('Convert to PNG or JPG'),
                onTap: () => Navigator.pop(context, 'image'),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: Text(single ? 'Make a PDF' : 'Combine into one PDF'),
                onTap: () => Navigator.pop(context, 'pdf'),
              ),
            ],
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case 'details':
        await showFileDetails(context, items.first);
      case 'rename':
        await _rename();
      case 'zip':
        await _zip(items);
      case 'unzip':
        await _unzip(items.first);
      case 'image' || 'pdf':
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => choice == 'pdf'
                ? ImagesToPdfScreen(files: items)
                : ConvertImagesScreen(files: items),
          ),
        );
        if (!mounted) return;
        setState(_selected.clear);
        await _load(_path, showSpinner: false);
    }
  }

  Future<void> _zip(List<FileItem> items) async {
    final first = items.first;
    final dot = first.name.lastIndexOf('.');
    final base = first.isDirectory || dot <= 0 ? first.name : first.name.substring(0, dot);

    final name = await showDialog<String>(
      context: context,
      builder: (_) => NameDialog(
        title: 'Compress to ZIP',
        confirmLabel: 'Compress',
        initial: items.length == 1 ? base : 'Archive',
        hint: 'File name',
        suffix: '.zip',
        existing: const {},
      ),
    );
    if (name == null || !mounted) return;

    setState(() => _loading = true);
    String? created;
    String? error;
    try {
      created = await _archive.createZip(items, _path, '$name.zip');
    } on FileSystemException catch (e) {
      error = e.message;
    } catch (_) {
      error = "Couldn't create the ZIP";
    }

    setState(_selected.clear);
    await _load(_path);
    if (!mounted) return;
    _toast(error ?? 'Created ${created!.split('/').last}');
  }

  Future<void> _unzip(FileItem item) async {
    setState(() => _loading = true);
    ExtractResult? result;
    String? error;
    try {
      result = await _archive.extractZip(item);
    } catch (_) {
      error = "Couldn't extract this ZIP. It may be damaged or password protected.";
    }

    setState(_selected.clear);
    await _load(_path);
    if (!mounted) return;

    if (result == null) {
      _toast(error!);
      return;
    }
    final extracted = result;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Extracted ${extracted.fileCount} ${extracted.fileCount == 1 ? 'file' : 'files'} to ${extracted.folderName}',
          ),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => _load(extracted.folderPath),
          ),
        ),
      );
  }

  Future<void> _zipTapMenu(FileItem item) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.unarchive_outlined),
              title: const Text('Extract here'),
              onTap: () => Navigator.pop(context, 'extract'),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open with another app'),
              onTap: () => Navigator.pop(context, 'open'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'extract') {
      await _unzip(item);
    } else {
      final result = await OpenFilex.open(item.path);
      if (result.type != ResultType.done && mounted) {
        _toast(result.type == ResultType.noAppToOpen
            ? 'No app can open this file'
            : result.message);
      }
    }
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
        title: Text('Move ${_count(items.length)} to trash?'),
        content: Text('You can restore them from Trash (in Settings) for ${TrashService.retentionDays} days.'),
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
            child: const Text('Move to trash'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _loading = true);
    final trash = TrashService(_service);
    final moved = <TrashEntry>[];
    var done = 0;
    String? error;
    for (final item in items) {
      try {
        moved.add(await trash.moveToTrash(item));
        done++;
      } on FileSystemException catch (e) {
        error = e.osError?.message ?? e.message;
      }
    }
    setState(() => _selected.clear());
    await _load(_path);
    if (!mounted) return;
    if (error != null || moved.isEmpty) {
      _toast(error ?? 'Nothing was deleted');
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Moved ${_count(done)} to trash'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              for (final e in moved) {
                try {
                  await trash.restore(e);
                } on FileSystemException catch (_) {}
              }
              if (mounted) await _load(_path, showSpinner: false);
            },
          ),
        ),
      );
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
          tooltip: widget.settings.gridView ? 'List view' : 'Grid view',
          icon: Icon(widget.settings.gridView ? Icons.view_list_outlined : Icons.grid_view_outlined),
          onPressed: () => widget.settings.setGridView(!widget.settings.gridView),
        ),
        IconButton(
          tooltip: _showHidden ? 'Hide hidden files' : 'Show hidden files',
          icon: Icon(_showHidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => widget.settings.setShowHidden(!_showHidden),
        ),
        PopupMenuButton<SortBy>(
          tooltip: 'Sort',
          icon: const Icon(Icons.sort),
          initialValue: _sortBy,
          onSelected: widget.settings.setSortBy,
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
      child: widget.settings.gridView
          ? GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 130,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.82,
        ),
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final item = _items[i];
          return FileGridTile(
            item: item,
            selected: _selected.contains(item.path),
            onTap: () => _onTap(item),
            onLongPress: () => _toggle(item),
          );
        },
      )
          : ListView.builder(
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
            _ActionButton(icon: Icons.more_horiz, label: 'More', onTap: _more),
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