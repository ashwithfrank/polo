import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/file_service.dart';
import '../services/zip_tool_service.dart';
import '../widgets/pdf_result.dart';

/// Opens a ZIP that has a password.
class ZipUnlockScreen extends StatefulWidget {
  const ZipUnlockScreen({super.key, required this.item});

  final FileItem item;

  @override
  State<ZipUnlockScreen> createState() => _ZipUnlockScreenState();
}

class _ZipUnlockScreenState extends State<ZipUnlockScreen> {
  final _password = TextEditingController();
  bool? _encrypted;
  String? _loadError;
  String? _error;
  bool _busy = false;
  bool _show = false;
  String? _folder;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    ZipToolService.isEncrypted(widget.item.path).then((v) {
      if (mounted) setState(() => _encrypted = v);
    }).catchError((Object e) {
      if (mounted) {
        setState(() => _loadError = e is FormatException ? e.message : "Couldn't open this ZIP");
      }
    });
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_encrypted == true && _password.text.isEmpty) {
      setState(() => _error = 'Type the password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final item = widget.item;
    final base = item.name.toLowerCase().endsWith('.zip')
        ? item.name.substring(0, item.name.length - 4)
        : item.name;
    try {
      final dir = await FileService().uniquePath(item.parentPath, base.isEmpty ? 'Extracted' : base);
      final n = await ZipToolService.extract(item.path, dir, _password.text);
      if (!mounted) return;
      setState(() {
        _folder = dir;
        _count = n;
      });
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't open this ZIP");
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 12);
    final folder = _folder;

    return Scaffold(
      appBar: AppBar(title: const Text('Open protected ZIP')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (folder != null) ...[
            SavedBanner(text: 'Extracted $_count ${_count == 1 ? 'item' : 'items'} to ${folder.split('/').last}'),
            const SizedBox(height: 16),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.folder_zip_outlined, color: scheme.primary),
            title: Text(widget.item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              _loadError ??
                  (_encrypted == null
                      ? 'Checking…'
                      : _encrypted!
                          ? 'Has a password'
                          : 'No password. It can just be extracted'),
              style: TextStyle(color: _loadError != null ? scheme.error : null),
            ),
          ),
          if (_encrypted == true && folder == null) ...[
            const SizedBox(height: 16),
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
            const SizedBox(height: 8),
            Text('Extracts into a new folder next to the ZIP.', style: muted),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: folder != null
              ? SavedActions(folderPath: folder)
              : FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _busy || _encrypted == null ? null : _run,
                  child: Text(_busy ? 'Working…' : 'Extract'),
                ),
        ),
      ),
    );
  }
}
