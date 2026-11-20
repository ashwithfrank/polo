import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/file_service.dart';
import '../services/pdf_tools_service.dart';
import '../widgets/pdf_result.dart';
import '../widgets/progress_dialog.dart';

/// Saves PDF pages as pictures (PNG or JPG).
class PdfToImagesScreen extends StatefulWidget {
  const PdfToImagesScreen({super.key, required this.item});

  final FileItem item;

  @override
  State<PdfToImagesScreen> createState() => _PdfToImagesScreenState();
}

class _PdfToImagesScreenState extends State<PdfToImagesScreen> {
  final _service = PdfToolsService(FileService());
  final _pages = TextEditingController();

  int? _count;
  String? _loadError;
  bool _jpg = false;
  int _dpi = 150;
  bool _busy = false;
  String? _error;
  String? _saved;
  String? _folder;

  static const _dpis = [72, 150, 200, 300];

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

  Future<void> _run() async {
    final count = _count;
    if (count == null) return;
    setState(() => _error = null);

    try {
      final pages = parsePageRanges(_pages.text, count);
      final detail = ValueNotifier<String>('');
      setState(() => _busy = true);
      final folder = await runWithProgress(
        context,
        'Saving pictures…',
        () => _service.toImages(
          widget.item.path,
          pages,
          jpg: _jpg,
          dpi: _dpi,
          onProgress: (done, total) => detail.value = 'Page $done of $total',
        ),
        detail: detail,
      );
      detail.dispose();
      if (!mounted) return;
      setState(() {
        _folder = folder;
        _saved =
            'Saved ${pages.length} ${pages.length == 1 ? 'picture' : 'pictures'} in the folder "${folder.split('/').last}"';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is FormatException ? e.message : "Couldn't save the pages");
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.titleSmall;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 12);
    final count = _count;
    final saved = _saved;
    final locked = _busy || saved != null;

    return Scaffold(
      appBar: AppBar(title: const Text('PDF to images')),
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
          if (count != null) ...[
            const SizedBox(height: 16),
            Text('Format', style: titleStyle),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('PNG')),
                ButtonSegment(value: true, label: Text('JPG')),
              ],
              selected: {_jpg},
              onSelectionChanged: locked ? null : (s) => setState(() => _jpg = s.first),
            ),
            const SizedBox(height: 4),
            Text(
              _jpg ? 'JPG makes smaller files.' : 'PNG is sharper, especially for text.',
              style: muted,
            ),
            const SizedBox(height: 16),
            Text('Quality', style: titleStyle),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final d in _dpis)
                  ChoiceChip(
                    label: Text('$d dpi'),
                    selected: _dpi == d,
                    onSelected: locked ? null : (_) => setState(() => _dpi = d),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text('150 is good for screens, 300 for printing.', style: muted),
            const SizedBox(height: 16),
            TextField(
              controller: _pages,
              enabled: !locked,
              decoration: const InputDecoration(
                labelText: 'Pages',
                hintText: 'All pages, or e.g. 1-3, 5',
              ),
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
              ? SavedActions(folderPath: _folder)
              : FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _busy || count == null ? null : _run,
                  child: Text(_busy ? 'Working…' : 'Save pictures'),
                ),
        ),
      ),
    );
  }
}
