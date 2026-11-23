import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/file_service.dart';
import '../services/output_location.dart';
import '../services/zip_tool_service.dart';
import '../widgets/pdf_result.dart';

/// Zips files and folders into a ZIP that needs a password (AES-256).
class ZipProtectScreen extends StatefulWidget {
  const ZipProtectScreen({super.key, required this.items});

  final List<FileItem> items;

  @override
  State<ZipProtectScreen> createState() => _ZipProtectScreenState();
}

class _ZipProtectScreenState extends State<ZipProtectScreen> {
  late final _name = TextEditingController(
    text: widget.items.length == 1 ? '${widget.items.first.name} (protected)' : 'Protected files',
  );
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _show = false;
  bool _busy = false;
  String? _error;
  String? _savedPath;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final pw = _password.text;
    var name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Type a name');
      return;
    }
    if (pw.length < 4) {
      setState(() => _error = 'Use at least 4 characters');
      return;
    }
    if (pw != _confirm.text) {
      setState(() => _error = "The two passwords don't match");
      return;
    }
    if (!name.toLowerCase().endsWith('.zip')) name = '$name.zip';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final dir = await OutputLocation.resolve(widget.items.first.parentPath, OutputKind.archives);
      final out = await FileService().uniquePath(dir, name);
      for (final i in widget.items) {
        if (i.isDirectory && out.startsWith('${i.path}/')) {
          throw const FormatException("Can't save the ZIP inside a folder you're zipping");
        }
      }
      await ZipToolService.create([for (final i in widget.items) i.path], out, pw);
      if (!mounted) return;
      setState(() => _savedPath = out);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't make the ZIP");
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 12);
    final saved = _savedPath;
    final n = widget.items.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Protected ZIP')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (saved != null) ...[
            SavedBanner(text: 'Saved ${saved.split('/').last}'),
            const SizedBox(height: 16),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.folder_zip_outlined, color: scheme.primary),
            title: Text('$n ${n == 1 ? 'item' : 'items'} to zip'),
            subtitle: Text(
              widget.items.map((e) => e.name).join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (saved == null) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'ZIP name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: !_show,
              decoration: InputDecoration(
                labelText: 'Password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _show = !_show),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              enabled: !_busy,
              obscureText: !_show,
              decoration: const InputDecoration(labelText: 'Type it again', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            Text(
              "Uses AES-256. Other apps (7-Zip, WinZip and most phone file managers) can open it with the "
              "password. Polo can't recover a forgotten password.",
              style: muted,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: saved != null
              ? SavedActions(openPath: saved)
              : FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _busy ? null : _run,
                  child: Text(_busy ? 'Working…' : 'Make protected ZIP'),
                ),
        ),
      ),
    );
  }
}
