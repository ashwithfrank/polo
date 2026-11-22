import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/file_service.dart';
import '../services/output_location.dart';
import '../services/pdf_lock_service.dart';
import '../widgets/pdf_result.dart';

/// Puts a password on a PDF, or takes the password off one that has it.
class PdfLockScreen extends StatefulWidget {
  const PdfLockScreen({super.key, required this.item});

  final FileItem item;

  @override
  State<PdfLockScreen> createState() => _PdfLockScreenState();
}

class _PdfLockScreenState extends State<PdfLockScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool? _locked;
  String? _loadError;
  String? _error;
  bool _busy = false;
  bool _show = false;
  String? _savedPath;

  @override
  void initState() {
    super.initState();
    PdfLockService.isLocked(widget.item.path).then((v) {
      if (mounted) setState(() => _locked = v);
    }).catchError((Object e) {
      if (mounted) {
        setState(() => _loadError = e is FormatException ? e.message : "Couldn't open this PDF");
      }
    });
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final unlock = _locked == true;
    final pw = _password.text;
    if (pw.isEmpty) {
      setState(() => _error = 'Type a password');
      return;
    }
    if (!unlock && pw != _confirm.text) {
      setState(() => _error = "The two passwords don't match");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final item = widget.item;
    final base = item.name.toLowerCase().endsWith('.pdf')
        ? item.name.substring(0, item.name.length - 4)
        : item.name;
    try {
      final dir = await OutputLocation.resolve(item.parentPath, OutputKind.documents);
      final out = await FileService()
          .uniquePath(dir, unlock ? '$base (unlocked).pdf' : '$base (locked).pdf');
      if (unlock) {
        await PdfLockService.unlock(item.path, out, pw);
      } else {
        await PdfLockService.lock(item.path, out, pw);
      }
      if (!mounted) return;
      setState(() => _savedPath = out);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't change this PDF");
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 12);
    final unlock = _locked == true;
    final saved = _savedPath;

    return Scaffold(
      appBar: AppBar(title: Text(_locked == null ? 'PDF password' : unlock ? 'Unlock PDF' : 'Lock PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (saved != null) ...[
            SavedBanner(text: 'Saved ${saved.split('/').last}'),
            const SizedBox(height: 16),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                unlock ? Icons.lock_open_outlined : Icons.lock_outline,
                color: Colors.red,
                size: 22,
              ),
            ),
            title: Text(widget.item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              _loadError ??
                  (_locked == null ? 'Checking…' : unlock ? 'Has a password' : 'No password yet'),
              style: TextStyle(color: _loadError != null ? scheme.error : null),
            ),
          ),
          if (_locked != null && saved == null) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: !_show,
              decoration: InputDecoration(
                labelText: unlock ? 'Current password' : 'New password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _show = !_show),
                ),
              ),
            ),
            if (!unlock) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _confirm,
                enabled: !_busy,
                obscureText: !_show,
                decoration: const InputDecoration(
                  labelText: 'Type it again',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              unlock
                  ? 'Saves a copy that opens without a password. The original stays locked.'
                  : "Saves a locked copy. Polo can't recover a forgotten password, so keep it safe. "
                      'The original stays unlocked.',
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
                  onPressed: _busy || _locked == null ? null : _run,
                  child: Text(_busy ? 'Working…' : unlock ? 'Unlock a copy' : 'Lock a copy'),
                ),
        ),
      ),
    );
  }
}
