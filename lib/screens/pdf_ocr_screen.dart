import 'dart:io';

import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/file_service.dart';
import '../services/ocr_service.dart';
import '../services/pdf_tools_service.dart';
import '../widgets/progress_dialog.dart';
import 'ocr_screen.dart';

/// Reads the text of a scanned PDF by looking at each page as a picture.
class PdfOcrScreen extends StatefulWidget {
  const PdfOcrScreen({super.key, required this.item});

  final FileItem item;

  @override
  State<PdfOcrScreen> createState() => _PdfOcrScreenState();
}

class _PdfOcrScreenState extends State<PdfOcrScreen> {
  final _service = PdfToolsService(FileService());
  final _pages = TextEditingController();

  int? _count;
  String? _loadError;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service.pageCount(widget.item.path).then((n) {
      if (mounted) setState(() => _count = n);
    }).catchError((Object e) {
      if (mounted) {
        setState(() => _loadError = e is FormatException ? e.message : "Couldn't open this PDF");
      }
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<String> _readPages(List<int> pages, ValueNotifier<String> detail) async {
    final doc = await PdfToolsService.open(widget.item.path);
    final tmp = await Directory.systemTemp.createTemp('polo_ocr');
    final out = StringBuffer();
    try {
      for (var i = 0; i < pages.length; i++) {
        detail.value = 'Page ${i + 1} of ${pages.length}';
        final n = pages[i];
        final png = await PdfToolsService.renderPng(doc.pages[n - 1], 3.0);
        final file = File('${tmp.path}/p$n.png');
        await file.writeAsBytes(png, flush: true);
        final text = await OcrService.read(file.path);
        await file.delete();
        if (text.isEmpty) continue;
        if (out.isNotEmpty) out.write('\n\n');
        if (pages.length > 1) out.write('--- Page $n ---\n');
        out.write(text);
      }
    } finally {
      await doc.dispose();
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    }
    return out.toString();
  }

  Future<void> _run() async {
    final count = _count;
    if (count == null) return;
    setState(() => _error = null);
    try {
      final pages = parsePageRanges(_pages.text, count);
      setState(() => _busy = true);
      final detail = ValueNotifier<String>('');
      final text = await runWithProgress(
        context,
        'Reading pages…',
        () => _readPages(pages, detail),
        detail: detail,
      );
      detail.dispose();
      if (!mounted) return;
      setState(() => _busy = false);
      if (text.trim().isEmpty) {
        setState(() => _error = 'No text was found. Try the other writing system');
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OcrScreen(
            path: widget.item.path,
            saveDir: widget.item.parentPath,
            preloaded: text,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is FormatException ? e.message : "Couldn't read the pages";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 12);
    final count = _count;

    return Scaffold(
      appBar: AppBar(title: const Text('Scanned PDF to text')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
            subtitle: Text(
              _loadError ?? (count == null ? 'Reading…' : '$count ${count == 1 ? 'page' : 'pages'}'),
              style: TextStyle(color: _loadError != null ? scheme.error : null),
            ),
          ),
          if (count != null) ...[
            const SizedBox(height: 16),
            Text('Writing system', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<OcrScript>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: OcrScript.latin, label: Text('Latin')),
                ButtonSegment(value: OcrScript.devanagari, label: Text('Devanagari')),
              ],
              selected: {OcrService.last},
              onSelectionChanged: _busy ? null : (v) => setState(() => OcrService.last = v.first),
            ),
            const SizedBox(height: 4),
            Text(OcrService.last.label, style: muted),
            const SizedBox(height: 16),
            TextField(
              controller: _pages,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Pages',
                hintText: 'All pages, or e.g. 1-3, 5',
              ),
            ),
            const SizedBox(height: 6),
            Text('Each page takes a few seconds. Works best on clear scans.', style: muted),
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
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _busy || count == null ? null : _run,
            child: Text(_busy ? 'Working…' : 'Read text'),
          ),
        ),
      ),
    );
  }
}
