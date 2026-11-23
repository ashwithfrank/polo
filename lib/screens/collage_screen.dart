import 'dart:io';

import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/collage_service.dart';
import '../services/file_service.dart';
import '../widgets/pdf_result.dart';

/// Puts 2 to 9 pictures together on one picture.
class CollageScreen extends StatefulWidget {
  const CollageScreen({super.key, required this.pictures});

  final List<FileItem> pictures;

  @override
  State<CollageScreen> createState() => _CollageScreenState();
}

class _CollageScreenState extends State<CollageScreen> {
  CollageLayout _layout = CollageLayout.grid;
  int _gap = 12;
  int _bgIndex = 0;
  bool _png = false;
  bool _busy = false;
  String? _error;
  String? _savedPath;

  static const _backgrounds = <(String, int)>[
    ('White', 0xFFFFFF),
    ('Cream', 0xFFF4E6),
    ('Grey', 0x888888),
    ('Black', 0x000000),
  ];

  late final List<FileItem> _pictures = widget.pictures.take(9).toList();

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final out = await CollageService(FileService()).make(
        _pictures,
        _layout,
        _gap,
        _backgrounds[_bgIndex].$2,
        _png,
      );
      if (!mounted) return;
      setState(() => _savedPath = out);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't make the collage");
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _preview() {
    final saved = _savedPath;
    if (saved != null) {
      // The real result, as it was saved.
      return GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                title: Text(saved.split('/').last),
              ),
              body: Center(
                child: InteractiveViewer(
                  maxScale: 6,
                  child: Image.file(File(saved)),
                ),
              ),
            ),
          ),
        ),
        child: Image.file(File(saved), fit: BoxFit.contain),
      );
    }
    final n = _pictures.length;
    final cols = _layout.columns(n);
    final rows = _layout.rows(n);
    final bg = Color(0xFF000000 | _backgrounds[_bgIndex].$2);
    final gap = _gap / 6;
    return AspectRatio(
      aspectRatio: cols / rows,
      child: Container(
        color: bg,
        padding: EdgeInsets.all(gap),
        child: Column(
          children: [
            for (var r = 0; r < rows; r++)
              Expanded(
                child: Row(
                  children: [
                    for (var c = 0; c < cols; c++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(gap / 2),
                          child: r * cols + c < n
                              ? Image.file(
                                  File(_pictures[r * cols + c].path),
                                  fit: BoxFit.cover,
                                  cacheWidth: 400,
                                  errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black12),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = Theme.of(context).textTheme.titleSmall;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 12);
    final saved = _savedPath;
    final locked = _busy || saved != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Collage')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (saved != null) ...[
            SavedBanner(text: 'Saved ${saved.split('/').last}'),
            const SizedBox(height: 16),
          ],
          ClipRRect(borderRadius: BorderRadius.circular(12), child: _preview()),
          const SizedBox(height: 6),
          Text(
            saved != null ? 'The saved picture. Tap to see it big.' : 'Preview. Changes as you pick options.',
            textAlign: TextAlign.center,
            style: muted,
          ),
          if (widget.pictures.length > 9) ...[
            const SizedBox(height: 8),
            Text('Only the first 9 pictures are used.', style: muted),
          ],
          const SizedBox(height: 16),
          Text('Layout', style: title),
          const SizedBox(height: 8),
          SegmentedButton<CollageLayout>(
            showSelectedIcon: false,
            segments: [
              for (final l in CollageLayout.values) ButtonSegment(value: l, label: Text(l.label)),
            ],
            selected: {_layout},
            onSelectionChanged: locked ? null : (v) => setState(() => _layout = v.first),
          ),
          const SizedBox(height: 16),
          Text('Space between pictures', style: title),
          Slider(
            min: 0,
            max: 40,
            divisions: 10,
            label: '$_gap',
            value: _gap.toDouble(),
            onChanged: locked ? null : (v) => setState(() => _gap = v.round()),
          ),
          Text('Background', style: title),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < _backgrounds.length; i++)
                ChoiceChip(
                  label: Text(_backgrounds[i].$1),
                  selected: _bgIndex == i,
                  onSelected: locked ? null : (_) => setState(() => _bgIndex = i),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Save as', style: title),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('JPG (smaller)')),
              ButtonSegment(value: true, label: Text('PNG (sharper)')),
            ],
            selected: {_png},
            onSelectionChanged: locked ? null : (v) => setState(() => _png = v.first),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: saved != null
              ? SavedActions(openPath: saved)
              : FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _busy ? null : _run,
                  child: Text(_busy ? 'Working…' : 'Make collage'),
                ),
        ),
      ),
    );
  }
}
