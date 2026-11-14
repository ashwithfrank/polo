import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/file_service.dart';
import '../services/pdf_service.dart';
import '../widgets/file_thumb.dart';
import '../widgets/open_file.dart';

class ImagesToPdfScreen extends StatefulWidget {
  const ImagesToPdfScreen({super.key, required this.files});

  final List<FileItem> files;

  @override
  State<ImagesToPdfScreen> createState() => _ImagesToPdfScreenState();
}

class _ImagesToPdfScreenState extends State<ImagesToPdfScreen> {
  final _service = PdfService(FileService());

  late final List<FileItem> _files = List.of(widget.files);
  late final TextEditingController _name = TextEditingController(text: _defaultName());

  PdfPageMode _mode = PdfPageMode.a4;
  double _quality = 85;
  bool _busy = false;
  String? _nameError;
  String? _error;
  String? _savedPath;

  String _defaultName() {
    if (widget.files.length != 1) return 'Images';
    final name = widget.files.first.name;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      _files.insert(newIndex, _files.removeAt(oldIndex));
    });
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Enter a name');
      return;
    }
    if (name.contains('/')) {
      setState(() => _nameError = "Names can't contain /");
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _nameError = null;
    });

    final first = _files.first.path;
    final dir = first.substring(0, first.lastIndexOf('/'));

    String? saved;
    String? error;
    try {
      saved = await _service.imagesToPdf(
        imagePaths: [for (final f in _files) f.path],
        dir: dir,
        fileName: '$name.pdf',
        mode: _mode,
        quality: _quality.round(),
      );
    } catch (e) {
      error = e is FormatException ? e.message : "Couldn't create the PDF";
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _savedPath = saved;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final saved = _savedPath;
    final locked = _busy || saved != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Images to PDF')),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        header: _buildOptions(context, locked),
        buildDefaultDragHandles: false,
        itemCount: _files.length,
        onReorderItem: locked ? (_, _) {} : _reorder,
        itemBuilder: (context, i) {
          final f = _files[i];
          return ListTile(
            key: ValueKey(f.path),
            contentPadding: EdgeInsets.zero,
            leading: FileThumb(
              path: f.path,
              fallback: Container(
                width: 42,
                height: 42,
                color: Colors.pink.withValues(alpha: 0.15),
                child: const Icon(Icons.image_outlined, color: Colors.pink),
              ),
            ),
            title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('Page ${i + 1} · ${f.sizeLabel}'),
            trailing: locked
                ? null
                : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_files.length > 1)
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
            onPressed: _busy ? null : _create,
            child: Text(_busy ? 'Creating PDF…' : 'Create PDF'),
          )
              : Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () => openFile(
                    context,
                    FileItem(
                      path: saved,
                      name: saved.split('/').last,
                      isDirectory: false,
                      size: 0,
                      modified: DateTime.now(),
                    ),
                  ),
                  child: const Text('Open PDF'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptions(BuildContext context, bool locked) {
    final scheme = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.titleSmall;
    final saved = _savedPath;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        if (saved != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Saved as ${saved.split('/').last}',
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text('Page size', style: titleStyle),
        const SizedBox(height: 8),
        SegmentedButton<PdfPageMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: PdfPageMode.a4, label: Text('A4')),
            ButtonSegment(value: PdfPageMode.fit, label: Text('Fit to image')),
          ],
          selected: {_mode},
          onSelectionChanged: locked ? null : (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text('Image quality', style: titleStyle),
            const Spacer(),
            Text('${_quality.round()}'),
          ],
        ),
        Slider(
          value: _quality,
          min: 40,
          max: 100,
          divisions: 12,
          onChanged: locked ? null : (v) => setState(() => _quality = v),
        ),
        Text(
          'Lower quality makes smaller PDFs.',
          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 12),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          enabled: !locked,
          decoration: InputDecoration(
            labelText: 'File name',
            suffixText: '.pdf',
            helperText: 'Saved next to the first image',
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
        Text(
          _files.length == 1 ? '1 image' : '${_files.length} images',
          style: titleStyle,
        ),
        if (!locked && _files.length > 1)
          Text(
            'Drag the handles to change the page order.',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 12),
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}