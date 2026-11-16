import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/file_service.dart';
import '../services/pdf_tools_service.dart';
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
    _every.dispose();
    super.dispose();
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