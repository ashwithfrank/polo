import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/file_service.dart';
import '../services/pdf_tools_service.dart';
import '../widgets/pdf_result.dart';
import 'pick_files_screen.dart';
import '../services/output_location.dart';

/// Joins several PDFs into one, in the order shown.
class PdfMergeScreen extends StatefulWidget {
  const PdfMergeScreen({super.key, required this.files});

  final List<FileItem> files;

  @override
  State<PdfMergeScreen> createState() => _PdfMergeScreenState();
}

class _PdfMergeScreenState extends State<PdfMergeScreen> {
  final _service = PdfToolsService(FileService());
  late final List<FileItem> _files = List.of(widget.files);
  final _name = TextEditingController(text: 'Merged');

  bool _busy = false;
  String? _nameError;
  String? _error;
  String? _saved;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final picked = await Navigator.of(context).push<List<FileItem>>(
      MaterialPageRoute(
        builder: (_) => PickFilesScreen(
          title: 'Add PDFs',
          accepts: (i) => i.extension == 'pdf',
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      for (final f in picked) {
        if (!_files.any((x) => x.path == f.path)) _files.add(f);
      }
    });
  }

  Future<void> _merge() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Enter a name');
      return;
    }
    if (name.contains('/')) {
      setState(() => _nameError = "Names can't contain /");
      return;
    }
    if (_files.length < 2) {
      setState(() => _error = 'Add at least two PDFs to merge');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _nameError = null;
    });

    String? saved;
    String? error;
    try {
      saved = await _service.merge(
        [for (final f in _files) f.path],
        _files.first.parentPath,
        '$name.pdf',
      );
    } catch (e) {
      error = e is FormatException ? e.message : "Couldn't merge these PDFs";
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _saved = saved;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final saved = _saved;
    final locked = _busy || saved != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Merge PDFs')),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        buildDefaultDragHandles: false,
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            if (saved != null) ...[
              SavedBanner(text: 'Saved as ${saved.split('/').last}'),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _name,
              enabled: !locked,
              decoration: InputDecoration(
                labelText: 'File name',
                suffixText: '.pdf',
                helperText: OutputLocation.hint('the first PDF', OutputKind.documents),
                errorText: _nameError,
              ),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Text(
                  '${_files.length} ${_files.length == 1 ? 'PDF' : 'PDFs'}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                if (!locked)
                  TextButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add more'),
                  ),
              ],
            ),
            if (!locked && _files.length > 1)
              Text(
                'Drag the handles to change the order.',
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 12),
              ),
            const SizedBox(height: 4),
          ],
        ),
        itemCount: _files.length,
        onReorderItem: locked
            ? (_, _) {}
            : (oldIndex, newIndex) => setState(() {
                  _files.insert(newIndex, _files.removeAt(oldIndex));
                }),
        itemBuilder: (context, i) {
          final f = _files[i];
          return ListTile(
            key: ValueKey(f.path),
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.picture_as_pdf_outlined, color: Colors.red, size: 22),
            ),
            title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${i + 1} · ${f.sizeLabel}'),
            trailing: locked
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _files.removeAt(i)),
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
                    ],
                  ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: saved == null
              ? FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _busy ? null : _merge,
                  child: Text(_busy ? 'Merging…' : 'Merge PDFs'),
                )
              : SavedActions(openPath: saved),
        ),
      ),
    );
  }
}
