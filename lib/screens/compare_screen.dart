import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/file_service.dart';
import '../services/inspect_service.dart';
import '../services/pdf_tools_service.dart';
import '../utils/format.dart';

const _textTypes = {
  'txt', 'md', 'markdown', 'csv', 'log', 'json', 'xml', 'html', 'htm', 'css', 'js', 'ts',
  'dart', 'java', 'kt', 'py', 'sh', 'yaml', 'yml', 'ini', 'conf', 'cfg',
  'properties', 'srt', 'gradle', 'toml', 'sql', 'c', 'cpp', 'h', 'rs', 'go',
};

/// Puts two files side by side: what differs, and whether they are the same.
class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key, required this.a, required this.b});

  final FileItem a;
  final FileItem b;

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  bool? _same;
  (int, int)? _sizeA, _sizeB;
  int? _pagesA, _pagesB;
  TextStats? _textA, _textB;
  TextDiff? _diff;
  bool _diffTried = false;
  bool _loading = true;

  FileItem get a => widget.a;
  FileItem get b => widget.b;

  bool get _bothImages => a.kind == FileKind.image && b.kind == FileKind.image;
  bool get _bothPdfs => a.kind == FileKind.pdf && b.kind == FileKind.pdf;
  bool get _bothText => _textTypes.contains(a.extension) && _textTypes.contains(b.extension);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final same = await InspectService.sameBytes(a.path, b.path);
      if (mounted) setState(() => _same = same);

      if (_bothImages) {
        _sizeA = await InspectService.imageSize(a.path);
        _sizeB = await InspectService.imageSize(b.path);
      }
      if (_bothPdfs) {
        final service = PdfToolsService(FileService());
        _pagesA = await service.pageCount(a.path);
        _pagesB = await service.pageCount(b.path);
      }
      if (_bothText) {
        _textA = await InspectService.textStats(a.path);
        _textB = await InspectService.textStats(b.path);
        if (!same) {
          _diff = await InspectService.textDiff(a.path, b.path);
          _diffTried = true;
        }
      }
    } catch (_) {
      // Whatever could not be read is left out.
    }
    if (mounted) setState(() => _loading = false);
  }

  String _date(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${a.dateLabelFor(d)}, ${two(d.hour)}:${two(d.minute)}';
  }

  Widget _banner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final same = _same;
    final (IconData icon, Color color, String title, String body) = same == null
        ? (Icons.hourglass_empty, scheme.primary, 'Comparing…', 'Reading both files')
        : same
        ? (
    Icons.check_circle,
    Colors.green,
    'Identical',
    'These two files have exactly the same content.',
    )
        : (
    Icons.difference_outlined,
    scheme.error,
    'Different',
    a.size == b.size
        ? 'Same size, but the content is not the same.'
        : 'The files differ in size and content.',
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: color),
                ),
                Text(body),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One row of the table. A value that differs from the other is bold.
  Widget _row(BuildContext context, String label, String x, String y) {
    final scheme = Theme.of(context).colorScheme;
    final differs = x != y;
    final style = TextStyle(
      fontSize: 13,
      fontWeight: differs ? FontWeight.w600 : FontWeight.normal,
      color: differs ? scheme.primary : null,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(x, style: style)),
              const SizedBox(width: 12),
              Expanded(child: Text(y, style: style)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, String title, List<Widget> children) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: scheme.primary)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _name(BuildContext context, String tag, FileItem f) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tag, style: TextStyle(fontSize: 12, color: scheme.primary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(f.name, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _diffView(BuildContext context, TextDiff diff) {
    final scheme = Theme.of(context).colorScheme;
    final shown = diff.lines.length;
    final total = diff.added + diff.removed;
    return _card(context, 'What changed', [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          '${diff.removed} removed, ${diff.added} added',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
      for (final l in diff.lines)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          color: (l.add ? Colors.green : scheme.error).withValues(alpha: 0.14),
          child: Text(
            '${l.add ? '+' : '-'} ${l.number}  ${l.text.isEmpty ? '(empty line)' : l.text}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      if (shown < total)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Showing the first $shown of $total changes',
            style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
        )
      else
        const SizedBox(height: 8),
      Text(
        '- is a line only in the first file (A). + is a line only in the second (B).',
        style: TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.6)),
      ),
      const SizedBox(height: 10),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final diff = _diff;
    final delta = b.size - a.size;

    return Scaffold(
      appBar: AppBar(title: const Text('Compare')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _name(context, 'A', a),
              const SizedBox(width: 12),
              _name(context, 'B', b),
            ],
          ),
          const SizedBox(height: 16),
          _banner(context),
          _card(context, 'Details', [
            _row(context, 'Size', a.sizeLabel, b.sizeLabel),
            if (delta != 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  delta > 0
                      ? 'B is ${formatBytes(delta)} bigger'
                      : 'B is ${formatBytes(-delta)} smaller',
                  style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.6)),
                ),
              ),
            _row(context, 'Modified', _date(a.modified), _date(b.modified)),
            _row(context, 'Type', a.extension.isEmpty ? 'File' : a.extension.toUpperCase(),
                b.extension.isEmpty ? 'File' : b.extension.toUpperCase()),
            _row(context, 'Location', a.parentPath, b.parentPath),
            if (_sizeA != null && _sizeB != null)
              _row(context, 'Dimensions', '${_sizeA!.$1} × ${_sizeA!.$2}', '${_sizeB!.$1} × ${_sizeB!.$2}'),
            if (_pagesA != null && _pagesB != null)
              _row(context, 'Pages', '$_pagesA', '$_pagesB'),
            if (_textA != null && _textB != null) ...[
              _row(context, 'Lines', '${_textA!.lines}', '${_textB!.lines}'),
              _row(context, 'Words', '${_textA!.words}', '${_textB!.words}'),
            ],
          ]),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (diff != null && (diff.added + diff.removed) > 0) _diffView(context, diff),
          if (_diffTried && diff == null && _same == false)
            _card(context, 'What changed', [
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('These files are too different or too big to show line by line.'),
              ),
            ]),
          if (_same == false && !_bothText)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'Polo shows line by line changes for text files only.',
                style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.6)),
              ),
            ),
        ],
      ),
    );
  }
}