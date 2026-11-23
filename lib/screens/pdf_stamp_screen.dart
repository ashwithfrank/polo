import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/file_item.dart';
import '../services/file_service.dart';
import '../services/output_location.dart';
import '../services/pdf_stamp_service.dart';
import '../services/pdf_tools_service.dart';
import '../widgets/pdf_page_preview.dart';
import '../widgets/pdf_result.dart';

enum StampMode { watermark, pageNumbers }

/// Adds a watermark, or page numbers, to every page of a PDF.
class PdfStampScreen extends StatefulWidget {
  const PdfStampScreen({super.key, required this.item, required this.mode});

  final FileItem item;
  final StampMode mode;

  @override
  State<PdfStampScreen> createState() => _PdfStampScreenState();
}

class _PdfStampScreenState extends State<PdfStampScreen> {
  final _text = TextEditingController(text: 'CONFIDENTIAL');
  final _start = TextEditingController(text: '1');

  // Watermark
  double _wmSize = 64;
  double _opacity = 0.25;
  bool _diagonal = true;

  // Page numbers
  int _format = 0;
  int _position = 1;
  double _numSize = 11;

  bool _busy = false;
  bool _previewing = false;
  String? _error;
  String? _savedPath;

  // The picture of the result, shown before and after saving.
  Uint8List? _thumb;
  PdfDocument? _doc;
  Directory? _tmp;
  int _previewCount = 0;

  static const _formats = ['{n}', 'Page {n}', '{n} / {total}', 'Page {n} of {total}'];
  static const _formatLabels = ['1', 'Page 1', '1 / 5', 'Page 1 of 5'];
  static const _positions = [
    'Bottom left', 'Bottom center', 'Bottom right',
    'Top left', 'Top center', 'Top right',
  ];

  bool get _watermark => widget.mode == StampMode.watermark;

  @override
  void dispose() {
    _text.dispose();
    _start.dispose();
    _doc?.dispose();
    try {
      _tmp?.deleteSync(recursive: true);
    } catch (_) {}
    super.dispose();
  }

  /// Any change to the options makes the old preview out of date.
  void _changed(VoidCallback change) {
    setState(() {
      change();
      if (_savedPath == null) _thumb = null;
    });
  }

  Future<void> _stampTo(String out) async {
    final item = widget.item;
    if (_watermark) {
      await PdfStampService.watermark(
        input: item.path,
        output: out,
        text: _text.text.trim(),
        size: _wmSize,
        opacity: _opacity,
        angle: _diagonal ? 45 : 0,
      );
    } else {
      await PdfStampService.pageNumbers(
        input: item.path,
        output: out,
        format: _formats[_format],
        position: _position,
        size: _numSize,
        start: int.tryParse(_start.text.trim()) ?? 1,
      );
    }
  }

  Future<void> _showPreview(String path) async {
    final doc = await PdfToolsService.open(path);
    final png = await PdfToolsService.renderPng(doc.pages.first, 1.4);
    if (!mounted) {
      doc.dispose();
      return;
    }
    final old = _doc;
    setState(() {
      _doc = doc;
      _thumb = png;
    });
    old?.dispose();
  }

  /// Makes the result in a temporary file so it can be looked at before saving.
  Future<void> _preview() async {
    if (_watermark && _text.text.trim().isEmpty) {
      setState(() => _error = 'Type the watermark text');
      return;
    }
    setState(() {
      _previewing = true;
      _error = null;
    });
    try {
      final tmp = _tmp ??= await Directory.systemTemp.createTemp('polo_stamp');
      final out = '${tmp.path}/preview_${_previewCount++}.pdf';
      await _stampTo(out);
      await _showPreview(out);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't make the preview");
    }
    if (mounted) setState(() => _previewing = false);
  }

  Widget _previewCard(BuildContext context) {
    final thumb = _thumb;
    final doc = _doc;
    if (thumb == null || doc == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final pages = doc.pages.length;
    final saved = _savedPath != null;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: () => showPdfPagePreview(
            context,
            doc: doc,
            pages: [for (var i = 1; i <= pages; i++) PdfPageRef(i)],
          ),
          child: Column(
            children: [
              Container(
                color: scheme.surfaceContainerHighest,
                width: double.infinity,
                height: 300,
                padding: const EdgeInsets.all(8),
                child: Image.memory(thumb, fit: BoxFit.contain),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  saved
                      ? 'The saved PDF. Tap to look through all $pages ${pages == 1 ? 'page' : 'pages'}'
                      : 'Preview, nothing saved yet. Tap to look through all $pages ${pages == 1 ? 'page' : 'pages'}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7), fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _run() async {
    if (_watermark && _text.text.trim().isEmpty) {
      setState(() => _error = 'Type the watermark text');
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
      final out = await FileService().uniquePath(
        dir,
        _watermark ? '$base (watermarked).pdf' : '$base (numbered).pdf',
      );
      await _stampTo(out);
      if (!mounted) return;
      setState(() => _savedPath = out);
      try {
        await _showPreview(out);
      } catch (_) {}
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
    final title = Theme.of(context).textTheme.titleSmall;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 12);
    final saved = _savedPath;
    final locked = _busy || saved != null;

    return Scaffold(
      appBar: AppBar(title: Text(_watermark ? 'Watermark PDF' : 'Page numbers')),
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
              child: const Icon(Icons.picture_as_pdf_outlined, color: Colors.red, size: 22),
            ),
            title: Text(widget.item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(widget.item.sizeLabel),
          ),
          const SizedBox(height: 8),
          if (_watermark) ...[
            TextField(
              controller: _text,
              enabled: !locked,
              onChanged: (_) => _changed(() {}),
              decoration: const InputDecoration(labelText: 'Watermark text', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Text('Direction', style: title),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('Diagonal')),
                ButtonSegment(value: false, label: Text('Straight')),
              ],
              selected: {_diagonal},
              onSelectionChanged: locked ? null : (v) => _changed(() => _diagonal = v.first),
            ),
            const SizedBox(height: 16),
            Text('Size', style: title),
            Slider(
              min: 24,
              max: 120,
              value: _wmSize,
              onChanged: locked ? null : (v) => _changed(() => _wmSize = v),
            ),
            Text('How see-through', style: title),
            Slider(
              min: 0.1,
              max: 0.7,
              value: _opacity,
              onChanged: locked ? null : (v) => _changed(() => _opacity = v),
            ),
            Text('Drawn in grey in the middle of every page. English letters only.', style: muted),
          ] else ...[
            Text('Style', style: title),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < _formats.length; i++)
                  ChoiceChip(
                    label: Text(_formatLabels[i]),
                    selected: _format == i,
                    onSelected: locked ? null : (_) => _changed(() => _format = i),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Where', style: title),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < _positions.length; i++)
                  ChoiceChip(
                    label: Text(_positions[i]),
                    selected: _position == i,
                    onSelected: locked ? null : (_) => _changed(() => _position = i),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Size', style: title),
            Slider(
              min: 8,
              max: 24,
              value: _numSize,
              onChanged: locked ? null : (v) => _changed(() => _numSize = v),
            ),
            TextField(
              controller: _start,
              enabled: !locked,
              onChanged: (_) => _changed(() {}),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Start counting at',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text('Saves a new copy. The original is not changed.', style: muted),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          _previewCard(context),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: saved != null
              ? SavedActions(openPath: saved)
              : Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        onPressed: _busy || _previewing ? null : _preview,
                        child: Text(_previewing ? 'Making…' : 'Preview'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        onPressed: _busy || _previewing ? null : _run,
                        child: Text(_busy ? 'Working…' : _watermark ? 'Add watermark' : 'Add page numbers'),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
