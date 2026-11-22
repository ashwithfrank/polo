import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/file_service.dart';
import '../widgets/pdf_result.dart';
import '../widgets/polo_message.dart';

const textExtensions = {
  'txt', 'md', 'markdown', 'csv', 'log', 'json', 'xml', 'html', 'htm', 'css', 'js', 'ts',
  'dart', 'java', 'kt', 'py', 'sh', 'yaml', 'yml', 'ini', 'conf', 'cfg',
  'properties', 'srt', 'gradle', 'toml', 'sql', 'c', 'cpp', 'h', 'rs', 'go',
};

/// Finds some text and swaps it for other text in one or more text files.
class FindReplaceScreen extends StatefulWidget {
  const FindReplaceScreen({super.key, required this.files});

  final List<FileItem> files;

  @override
  State<FindReplaceScreen> createState() => _FindReplaceScreenState();
}

class _FindReplaceScreenState extends State<FindReplaceScreen> {
  final _find = TextEditingController();
  final _replace = TextEditingController();
  bool _caseSensitive = false;
  bool _overwrite = false;
  bool _busy = false;
  Map<String, int> _counts = {};
  String? _error;
  int _changedFiles = 0;
  String? _doneFolder;

  @override
  void dispose() {
    _find.dispose();
    _replace.dispose();
    super.dispose();
  }

  Future<void> _count() async {
    final find = _find.text;
    if (find.isEmpty) {
      setState(() => _counts = {});
      return;
    }
    final paths = [for (final f in widget.files) f.path];
    final cs = _caseSensitive;
    final counts = await Isolate.run(() {
      final out = <String, int>{};
      final re = RegExp(RegExp.escape(find), caseSensitive: cs);
      for (final p in paths) {
        try {
          out[p] = re.allMatches(File(p).readAsStringSync()).length;
        } catch (_) {
          out[p] = -1;
        }
      }
      return out;
    });
    if (mounted && find == _find.text) setState(() => _counts = counts);
  }

  Future<void> _apply() async {
    final find = _find.text;
    final replace = _replace.text;
    if (find.isEmpty) {
      setState(() => _error = 'Type the text to find');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = FileService();
      var changed = 0;
      String? folder;
      for (final f in widget.files) {
        if ((_counts[f.path] ?? 0) <= 0) continue;
        final re = RegExp(RegExp.escape(find), caseSensitive: _caseSensitive);
        final text = await File(f.path).readAsString();
        final result = text.replaceAll(re, replace);
        if (_overwrite) {
          await File(f.path).writeAsString(result, flush: true);
          folder = f.parentPath;
        } else {
          final dot = f.name.lastIndexOf('.');
          final name = dot > 0
              ? '${f.name.substring(0, dot)} (edited)${f.name.substring(dot)}'
              : '${f.name} (edited)';
          final out = await service.uniquePath(f.parentPath, name);
          await File(out).writeAsString(result, flush: true);
          folder = f.parentPath;
        }
        changed++;
      }
      if (!mounted) return;
      if (changed == 0) {
        setState(() {
          _busy = false;
          _error = 'Nothing to change. The text was not found';
        });
        return;
      }
      setState(() {
        _busy = false;
        _changedFiles = changed;
        _doneFolder = folder;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showPoloMessage(context, "Couldn't change the files");
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 12);
    final total = _counts.values.where((v) => v > 0).fold<int>(0, (a, b) => a + b);
    final done = _doneFolder != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Find and replace')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (done) ...[
            SavedBanner(
              text: _overwrite
                  ? 'Changed $_changedFiles ${_changedFiles == 1 ? 'file' : 'files'}'
                  : 'Saved $_changedFiles edited ${_changedFiles == 1 ? 'copy' : 'copies'} next to the originals',
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _find,
            enabled: !_busy && !done,
            onChanged: (_) => _count(),
            decoration: const InputDecoration(labelText: 'Find', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _replace,
            enabled: !_busy && !done,
            decoration: const InputDecoration(labelText: 'Replace with', border: OutlineInputBorder()),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Match capital letters'),
            value: _caseSensitive,
            onChanged: _busy || done
                ? null
                : (v) {
                    setState(() => _caseSensitive = v);
                    _count();
                  },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Change the original files'),
            subtitle: Text(
              _overwrite ? 'The originals are overwritten. This cannot be undone' : 'Saves edited copies instead',
            ),
            value: _overwrite,
            onChanged: _busy || done ? null : (v) => setState(() => _overwrite = v),
          ),
          const SizedBox(height: 8),
          Text(
            _find.text.isEmpty
                ? '${widget.files.length} ${widget.files.length == 1 ? 'file' : 'files'} chosen'
                : '$total ${total == 1 ? 'match' : 'matches'} in ${_counts.values.where((v) => v > 0).length} of ${widget.files.length} files',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          for (final f in widget.files)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Text(
                (_counts[f.path] ?? 0) < 0 ? "Can't read" : '${_counts[f.path] ?? 0}',
                style: muted,
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: done
              ? SavedActions(folderPath: _doneFolder)
              : FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _busy || total == 0 ? null : _apply,
                  child: Text(_busy ? 'Working…' : 'Replace'),
                ),
        ),
      ),
    );
  }
}
