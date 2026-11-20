import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../models/file_item.dart';
import '../services/file_service.dart';
import '../services/pdf_tools_service.dart';
import '../widgets/pdf_page_preview.dart';
import '../widgets/pdf_result.dart';
import '../widgets/progress_dialog.dart';

enum _SplitMode { extract, each, every }

/// Pull pages out of a PDF, or split it into several PDFs.
class PdfSplitScreen extends StatefulWidget {
  const PdfSplitScreen({super.key, required this.item});

  final FileItem item;

  @override
  State<PdfSplitScreen> createState() => _PdfSplitScreenState();
}

class _PdfSplitScreenState extends State<PdfSplitScreen> {
  final _service = PdfToolsService(FileService());
  final _pages = TextEditingController();
  final _every = TextEditingController(text: '2');

  int? _count;
  String? _loadError;
  _SplitMode _mode = _SplitMode.extract;
  bool _busy = false;
  String? _error;
  String? _savedText;
  String? _savedFile;

  pdfrx.PdfDocument? _doc;
  final Map<int, Future<Uint8List>> _thumbs = {};

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
        _count = doc.pages.length;
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
    _pages.dispose();
    _every.dispose();
    super.dispose();
  }

  Future<Uint8List> _thumb(int page) {
    return _thumbs.putIfAbsent(
      page,
          () => PdfToolsService.renderPng(_doc!.pages[page - 1], 0.4),
    );
  }

  /// The groups of pages that will become files, or null while the input
  /// can't be read yet. In extract mode there is one group.
  List<List<int>>? _groups() {
    final count = _count;
    if (count == null) return null;
    try {
      if (_mode == _SplitMode.extract) {
        return [parsePageRanges(_pages.text, count)];
      }
      final n = _mode == _SplitMode.each ? 1 : int.tryParse(_every.text.trim()) ?? 0;
      if (n < 1) return null;
      return [
        for (var start = 1; start <= count; start += n)
          [for (var p = start; p < start + n && p <= count; p++) p],
      ];
    } on FormatException {
      return null;
    }
  }

  Widget _tile(BuildContext context, int page, String caption, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 84,
          child: Column(
            children: [
              Container(
                width: 84,
                height: 112,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                clipBehavior: Clip.antiAlias,
                child: FutureBuilder<Uint8List>(
                  future: _thumb(page),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return Center(
                        child: snap.hasError
                            ? const Icon(Icons.broken_image_outlined)
                            : const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    return Image.memory(snap.data!, fit: BoxFit.contain);
                  },
                ),
              ),
              const SizedBox(height: 4),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A row of small pages showing what the result will contain. Tap one to
  /// see it big.
  Widget _resultPreview(BuildContext context) {
    final groups = _groups();
    final doc = _doc;
    if (groups == null || doc == null || groups.isEmpty || groups.first.isEmpty) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final extract = _mode == _SplitMode.extract;
    const cap = 40;

    final tiles = <Widget>[];
    if (extract) {
      final pages = groups.first;
      for (var i = 0; i < pages.length && i < cap; i++) {
        tiles.add(_tile(
          context,
          pages[i],
          'Page ${pages[i]}',
              () => showPdfPagePreview(
            context,
            doc: doc,
            pages: [for (final p in pages) PdfPageRef(p)],
            start: i,
          ),
        ));
      }
    } else {
      for (var i = 0; i < groups.length && i < cap; i++) {
        final g = groups[i];
        tiles.add(_tile(
          context,
          g.first,
          g.length == 1 ? 'File ${i + 1} · p${g.first}' : 'File ${i + 1} · p${g.first}-${g.last}',
              () => showPdfPagePreview(
            context,
            doc: doc,
            pages: [for (final p in g) PdfPageRef(p)],
          ),
        ));
      }
    }

    final total = extract ? groups.first.length : groups.length;
    final label = extract
        ? '${groups.first.length} ${groups.first.length == 1 ? 'page' : 'pages'} in the new PDF'
        : '$total ${total == 1 ? 'file' : 'files'} will be made';

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Result preview', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            '$label. Tap one to view it.',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 12),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 140,
            child: ListView(scrollDirection: Axis.horizontal, children: tiles),
          ),
          if (total > cap)
            Text(
              'Showing the first $cap of $total',
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 12),
            ),
        ],
      ),
    );
  }

  Future<void> _run() async {
    final count = _count;
    if (count == null) return;
    final item = widget.item;
    final base = baseName(item.name);

    setState(() {
      _error = null;
    });

    try {
      switch (_mode) {
        case _SplitMode.extract:
          final pages = parsePageRanges(_pages.text, count);
          setState(() => _busy = true);
          final out = await _service.extract(
            item.path,
            pages,
            item.parentPath,
            '$base (extract).pdf',
          );
          if (!mounted) return;
          setState(() {
            _savedText =
            'Saved ${pages.length} ${pages.length == 1 ? 'page' : 'pages'} as ${out.split('/').last}';
            _savedFile = out;
          });
        case _SplitMode.each:
        case _SplitMode.every:
          final n = _mode == _SplitMode.each ? 1 : int.tryParse(_every.text.trim()) ?? 0;
          if (n < 1) throw const FormatException('Enter how many pages per file');
          final groups = <List<int>>[
            for (var start = 1; start <= count; start += n)
              [for (var p = start; p < start + n && p <= count; p++) p],
          ];
          final detail = ValueNotifier<String>('');
          setState(() => _busy = true);
          final folder = await runWithProgress(
            context,
            'Splitting…',
                () => _service.splitToFolder(
              item.path,
              groups,
              folderName: _mode == _SplitMode.each ? '$base pages' : '$base parts',
              filePrefix: _mode == _SplitMode.each ? '$base page' : '$base part',
              onProgress: (done, total) => detail.value = '$done of $total',
            ),
            detail: detail,
          );
          detail.dispose();
          if (!mounted) return;
          setState(() {
            _savedText =
            'Saved ${groups.length} ${groups.length == 1 ? 'file' : 'files'} in the folder "${folder.split('/').last}"';
            _savedFile = null;
          });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is FormatException ? e.message : "Couldn't split this PDF");
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.titleSmall;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 12);
    final count = _count;
    final saved = _savedText;
    final locked = _busy || saved != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Split and extract')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (saved != null) ...[
            SavedBanner(text: saved),
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
            subtitle: Text(
              _loadError ?? (count == null ? 'Reading…' : '$count ${count == 1 ? 'page' : 'pages'}'),
              style: TextStyle(color: _loadError != null ? scheme.error : null),
            ),
          ),
          const SizedBox(height: 12),
          if (count != null) ...[
            Text('What to do', style: titleStyle),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: const Text('Extract pages'),
                  selected: _mode == _SplitMode.extract,
                  onSelected: locked ? null : (_) => setState(() => _mode = _SplitMode.extract),
                ),
                ChoiceChip(
                  label: const Text('One file per page'),
                  selected: _mode == _SplitMode.each,
                  onSelected: locked ? null : (_) => setState(() => _mode = _SplitMode.each),
                ),
                ChoiceChip(
                  label: const Text('Every N pages'),
                  selected: _mode == _SplitMode.every,
                  onSelected: locked ? null : (_) => setState(() => _mode = _SplitMode.every),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_mode == _SplitMode.extract) ...[
              TextField(
                controller: _pages,
                enabled: !locked,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  labelText: 'Pages',
                  hintText: 'e.g. 1-3, 5, 8-',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Separate pages with commas. "8-" means page 8 to the end. '
                    'The order you type is the order in the new PDF.',
                style: muted,
              ),
            ] else if (_mode == _SplitMode.every) ...[
              TextField(
                controller: _every,
                enabled: !locked,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Pages in each file'),
              ),
              const SizedBox(height: 6),
              Text('The last file may have fewer pages.', style: muted),
            ] else
              Text(
                'Every page becomes its own PDF, saved in a new folder next to the original.',
                style: muted,
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
            if (saved == null) _resultPreview(context),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: saved != null
              ? SavedActions(openPath: _savedFile)
              : FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _busy || count == null ? null : _run,
            child: Text(_busy ? 'Working…' : 'Go'),
          ),
        ),
      ),
    );
  }
}