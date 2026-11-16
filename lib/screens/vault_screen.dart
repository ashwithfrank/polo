import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/file_service.dart';
import '../services/vault_service.dart';
import '../widgets/open_file.dart';
import '../widgets/polo_message.dart';
import '../widgets/progress_dialog.dart';
import 'pick_files_screen.dart';
import 'viewer/viewer_screen.dart';

enum _Stage { loading, setup, locked, open }

/// A password-protected place to keep private files. Files are encrypted on
/// the device and nothing is ever sent anywhere.
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> with WidgetsBindingObserver {
  static final _tempDir = Directory('${Directory.systemTemp.path}/polo_vault');

  final _password = TextEditingController();
  final _confirm = TextEditingController();

  _Stage _stage = _Stage.loading;
  Uint8List? _key;
  List<VaultEntry> _entries = const [];
  bool _busy = false;
  bool _understood = false;
  bool _hidePassword = true;
  String? _error;

  /// True while another app is showing a file, so leaving Polo doesn't lock
  /// the vault.
  bool _external = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clearTemp();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _external = false;
    } else if (state == AppLifecycleState.paused && !_external && _stage == _Stage.open) {
      _lock();
    }
  }

  Future<void> _start() async {
    final exists = await VaultService.exists();
    if (!mounted) return;
    setState(() => _stage = exists ? _Stage.locked : _Stage.setup);
  }

  void _clearTemp() {
    try {
      if (_tempDir.existsSync()) _tempDir.deleteSync(recursive: true);
    } catch (_) {}
  }

  void _lock() {
    _clearTemp();
    _password.clear();
    _confirm.clear();
    setState(() {
      _key = null;
      _entries = const [];
      _error = null;
      _stage = _Stage.locked;
    });
  }

  Future<void> _refresh() async {
    final key = _key;
    if (key == null) return;
    final list = await VaultService.list(key);
    if (mounted) setState(() => _entries = list);
  }

  // ---- Setting up and unlocking -------------------------------------------

  Future<void> _create() async {
    final pw = _password.text;
    if (pw.length < 6) {
      setState(() => _error = 'Use at least 6 characters');
      return;
    }
    if (pw != _confirm.text) {
      setState(() => _error = "The two passwords don't match");
      return;
    }
    if (!_understood) {
      setState(() => _error = 'Please tick the box to confirm');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final key = await VaultService.create(pw);
      if (!mounted) return;
      _password.clear();
      _confirm.clear();
      setState(() {
        _key = key;
        _entries = const [];
        _stage = _Stage.open;
      });
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't create the vault");
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _unlock() async {
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final key = await VaultService.unlock(_password.text);
      if (!mounted) return;
      if (key == null) {
        setState(() => _error = 'Wrong password');
      } else {
        _password.clear();
        setState(() {
          _key = key;
          _stage = _Stage.open;
        });
        await _refresh();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is FormatException ? e.message : "Couldn't unlock the vault");
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _forgot() async {
    final erase = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forgot your password?'),
        content: const Text(
          "There is no way to recover it, and Polo can't unlock your files without it. "
              'That is what keeps them safe.\n\n'
              'You can erase the vault and start again. Everything inside it will be '
              'deleted for good.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Erase vault'),
          ),
        ],
      ),
    );
    if (erase != true || !mounted) return;
    await VaultService.erase();
    if (!mounted) return;
    _password.clear();
    setState(() {
      _error = null;
      _stage = _Stage.setup;
    });
  }

  // ---- Files ----------------------------------------------------------------

  Future<void> _add() async {
    final key = _key;
    if (key == null) return;

    final picked = await Navigator.of(context).push<List<FileItem>>(
      MaterialPageRoute(
        builder: (_) => PickFilesScreen(
          title: 'Choose files to lock',
          accepts: (item) => !item.isDirectory,
        ),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;

    var deleteOriginals = true;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Lock ${picked.length} ${picked.length == 1 ? 'file' : 'files'}?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Large files can take a little while.'),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: deleteOriginals,
                onChanged: (v) => setLocal(() => deleteOriginals = v ?? false),
                title: const Text('Delete the originals'),
                subtitle: const Text(
                  'Each original is deleted for good, only after its locked copy is '
                      'checked. It does not go to the trash.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Lock'),
            ),
          ],
        ),
      ),
    );
    if (go != true || !mounted) return;

    final detail = ValueNotifier<String>('');
    final failed = <String>[];
    var locked = 0;
    try {
      await runWithProgress(
        context,
        'Locking files…',
            () async {
          for (var i = 0; i < picked.length; i++) {
            final f = picked[i];
            detail.value = '${i + 1} of ${picked.length} · ${f.name}';
            final error = await VaultService.add(key, f.path, verify: deleteOriginals);
            if (error != null) {
              failed.add('${f.name}: $error');
              continue;
            }
            locked++;
            if (deleteOriginals) {
              try {
                await File(f.path).delete();
              } catch (_) {
                failed.add("${f.name}: locked, but the original couldn't be deleted");
              }
            }
          }
        },
        detail: detail,
      );
    } finally {
      detail.dispose();
    }
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;

    if (failed.isEmpty) {
      showPoloMessage(context, 'Locked $locked ${locked == 1 ? 'file' : 'files'}');
    } else {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Locked $locked of ${picked.length}'),
          content: SingleChildScrollView(child: Text(failed.join('\n\n'))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
    }
  }

  Future<void> _open(VaultEntry entry) async {
    final key = _key;
    if (key == null) return;

    _clearTemp();
    await _tempDir.create(recursive: true);
    if (!mounted) return;
    final safe = entry.name.replaceAll('/', '_');
    final out = '${_tempDir.path}/$safe';

    final error = await runWithProgress(
      context,
      'Unlocking ${entry.name}…',
          () => VaultService.restore(key, entry, out),
    );
    if (!mounted) return;
    if (error != null) {
      showPoloMessage(context, error);
      return;
    }

    final item = FileItem(
      path: out,
      name: safe,
      isDirectory: false,
      size: entry.size,
      modified: entry.modified,
    );
    _external = true;
    await openFile(context, item);
    // Polo's own viewer doesn't leave the app; other apps do and set this back
    // when Polo returns.
    if (canView(item)) _external = false;
  }

  Future<void> _restore(VaultEntry entry) async {
    final key = _key;
    if (key == null) return;

    final dir = '${FileService.rootPath}/Download/Polo restored';
    await Directory(dir).create(recursive: true);
    final dest = await FileService().uniquePath(dir, entry.name);
    if (!mounted) return;

    final error = await runWithProgress(
      context,
      'Unlocking ${entry.name}…',
          () => VaultService.restore(key, entry, dest),
    );
    if (!mounted) return;
    showPoloMessage(
      context,
      error ?? 'Saved in Download/Polo restored',
    );
  }

  Future<void> _remove(VaultEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete from the vault?'),
        content: Text(
          '"${entry.name}" will be deleted for good. If you want to keep it, '
              'save a copy first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await VaultService.remove(entry);
    await _refresh();
  }

  IconData _icon(VaultEntry e) {
    final item = FileItem(
      path: e.name,
      name: e.name,
      isDirectory: false,
      size: e.size,
      modified: e.modified,
    );
    return switch (item.kind) {
      FileKind.image => Icons.image_outlined,
      FileKind.video => Icons.movie_outlined,
      FileKind.audio => Icons.music_note_outlined,
      FileKind.pdf => Icons.picture_as_pdf_outlined,
      FileKind.document => Icons.description_outlined,
      FileKind.archive => Icons.folder_zip_outlined,
      FileKind.apk => Icons.android,
      _ => Icons.insert_drive_file_outlined,
    };
  }

  // ---- Screens ----------------------------------------------------------------

  Widget _passwordField(TextEditingController c, String label, {VoidCallback? onSubmit}) {
    return TextField(
      controller: c,
      enabled: !_busy,
      obscureText: _hidePassword,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: onSubmit == null ? TextInputAction.next : TextInputAction.done,
      onSubmitted: onSubmit == null ? null : (_) => onSubmit(),
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _hidePassword = !_hidePassword),
        ),
      ),
    );
  }

  Widget _gate(BuildContext context, {required bool setup}) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.65));

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 16),
        Icon(Icons.lock_outline, size: 56, color: scheme.primary),
        const SizedBox(height: 16),
        Text(
          setup ? 'Create your vault' : 'Vault is locked',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          setup
              ? 'Files you lock here are encrypted on this phone. Nothing is sent anywhere.'
              : 'Enter your password to see your files.',
          textAlign: TextAlign.center,
          style: muted,
        ),
        const SizedBox(height: 24),
        _passwordField(
          _password,
          'Password',
          onSubmit: setup ? null : _unlock,
        ),
        if (setup) ...[
          const SizedBox(height: 12),
          _passwordField(_confirm, 'Repeat the password', onSubmit: _create),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _understood,
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                _understood = v ?? false;
                _error = null;
              }),
              title: const Text(
                "If I forget this password, my files can't be recovered. There is no reset.",
                style: TextStyle(fontSize: 13),
              ),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: scheme.error)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _busy ? null : (setup ? _create : _unlock),
          child: Text(
            _busy ? (setup ? 'Creating…' : 'Unlocking…') : (setup ? 'Create vault' : 'Unlock'),
          ),
        ),
        if (!setup)
          TextButton(
            onPressed: _busy ? null : _forgot,
            child: const Text('Forgot password?'),
          ),
      ],
    );
  }

  Widget _list(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_open_outlined, size: 48, color: scheme.primary),
              const SizedBox(height: 12),
              Text('The vault is empty', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'Tap "Lock files" to add photos, documents or anything private.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: _entries.length,
      itemBuilder: (context, i) {
        final e = _entries[i];
        final item = FileItem(
          path: e.name,
          name: e.name,
          isDirectory: false,
          size: e.size,
          modified: e.modified,
        );
        return ListTile(
          leading: Icon(_icon(e)),
          title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${item.sizeLabel} · ${item.dateLabel}'),
          onTap: () => _open(e),
          trailing: PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'open':
                  _open(e);
                case 'restore':
                  _restore(e);
                case 'remove':
                  _remove(e);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'open', child: Text('Open')),
              PopupMenuItem(value: 'restore', child: Text('Save a copy to Downloads')),
              PopupMenuItem(value: 'remove', child: Text('Delete from vault')),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final open = _stage == _Stage.open;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vault'),
        actions: [
          if (open)
            IconButton(
              tooltip: 'Lock now',
              icon: const Icon(Icons.lock_outline),
              onPressed: _lock,
            ),
        ],
      ),
      body: switch (_stage) {
        _Stage.loading => const Center(child: CircularProgressIndicator()),
        _Stage.setup => _gate(context, setup: true),
        _Stage.locked => _gate(context, setup: false),
        _Stage.open => _list(context),
      },
      floatingActionButton: open
          ? FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Lock files'),
      )
          : null,
    );
  }
}