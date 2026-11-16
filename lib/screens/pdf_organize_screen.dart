import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../models/file_item.dart';
import '../services/file_service.dart';
import '../services/pdf_tools_service.dart';
import '../widgets/pdf_result.dart';

/// Rotate, reorder and delete the pages of a PDF. The result is a new file.
class PdfOrganizeScreen extends StatefulWidget {
  const PdfOrganizeScreen({super.key, required this.item});

  final FileItem item;

  @override
  State<PdfOrganizeScreen> createState() => _PdfOrganizeScreenState();
}

class _PdfOrganizeScreenState extends State<PdfOrganizeScreen> {
  final _service = PdfToolsService(FileService());

  pdfrx.PdfDocument? _doc;
  List<PageEdit> _edits = [];
  final Map<int, Future<Uint8List>> _thumbs = {};
  String? _loadError;

  bool _busy = false;
  String? _error;
  String? _saved;

  @override
  void initState() {
    super.initState();
    PdfToolsService.open(widget.item.path).then((doc) {
      if (!mounted) {
        doc.dispose();
        return;
      }
      setState(() {
        _doc = doc;
        _edits = [for (var i = 0; i < doc.pages.length; i++) PageEdit(i)];
      });
    }).catchError((Object e) {
      if (mounted) {
        setState(() => _loadError = e is FormatException ? e.message : "Couldn't open this PDF");
      }
    });
  }

  @override
  void dispose() {
    _doc?.dispose();
    super.dispose();
  }

  Future<Uint8List> _thumb(int index) {
    return _thumbs.putIfAbsent(
      index,
          () => PdfToolsService.renderPng(_doc!.pages[index], 0.4),
    );
  }

  bool get _changed {
    final doc = _doc;
    if (doc == null) return false;
    if (_edits.length != doc.pages.length) return true;
    for (var i = 0; i < _edits.length; i++) {
      if (_edits[i].index != i || _edits[i].turns % 4 != 0) return true;
    }
    return false;
  }

  Future<void> _save() async {
    if (_edits.isEmpty) {
      setState(() => _error = 'Keep at least one page');
      return;
    }
    if (!_changed) {
      setState(() => _error = 'Nothing has changed yet');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    String? saved;
    String? error;
    try {
      final item = widget.item;
      saved = await _service.organize(
        item.path,
        _edits,
        item.parentPath,
        '${baseName(item.name)} (edited).pdf',
      );
    } catch (e) {
      error = e is FormatException ? e.message : "Couldn't save this PDF";
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

    Widget body;
    if (_loadError != null) {
      body = Center(child: Text(_loadError!, style: TextStyle(color: scheme.error)));
    } else if (_doc == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        buildDefaultDragHandles: false,
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            if (saved != null) ...[
              SavedBanner(text: 'Saved as ${saved.split('/').last}'),
              const SizedBox(height: 12),
            ],
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: scheme.error)),
              const SizedBox(height: 8),
            ],
            Text(
              '${_edits.length} of ${_doc!.pages.length} pages'
                  '${locked ? '' : ' · drag to reorder, rotate or remove'}',
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65), fontSize: 13),
            ),
            const SizedBox(height: 8),
          ],
        ),
        itemCount: _edits.length,
        onReorderItem: locked
            ? (_, _) {}
            : (oldIndex, newIndex) => setState(() {
          _edits.insert(newIndex, _edits.removeAt(oldIndex));
        }),
        itemBuilder: (context, i) {
          final e = _edits[i];
          return Container(
            key: ValueKey('page-${e.index}'),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  height: 96,
                  child: FutureBuilder<Uint8List>(
                    future: _thumb(e.index),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return Center(
                          child: snap.hasError
                              ? const Icon(Icons.broken_image_outlined)
                              : const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      return AnimatedRotation(
                        turns: e.turns / 4,
                        duration: const Duration(milliseconds: 200),
                        child: Image.memory(snap.data!, fit: BoxFit.contain),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Page ${e.index + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        e.turns % 4 == 0 ? 'Position ${i + 1}' : 'Position ${i + 1} · turned',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!locked) ...[
                  IconButton(
                    tooltip: 'Rotate',
                    icon: const Icon(Icons.rotate_right),
                    onPressed: () => setState(() => e.turns = e.turns + 1),
                  ),
                  IconButton(
                    tooltip: 'Remove page',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _edits.removeAt(i)),
                  ),
                  ReorderableDragStartListener(
                    index: i,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Organize pages')),
      body: body,
      bottomNavigationBar: _doc == null
          ? null
          : SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: saved == null
              ? FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving…' : 'Save as a new PDF'),
          )
              : SavedActions(openPath: saved),
        ),
      ),
    );
  }
}