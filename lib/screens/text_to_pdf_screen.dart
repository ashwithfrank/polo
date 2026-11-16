import 'dart:io';

import 'package:flutter/material.dart';

import '../services/file_service.dart';
import '../services/text_pdf_service.dart';
import '../widgets/pdf_result.dart';
import '../widgets/progress_dialog.dart';

/// Turns text or Markdown into a PDF. Start from a file's text, or type and
/// paste your own.
class TextToPdfScreen extends StatefulWidget {
  const TextToPdfScreen({
    super.key,
    this.initialText = '',
    this.name = 'Document',
    this.dir,
    this.markdown = false,
  });

  final String initialText;
  final String name;

  /// Where to save. Defaults to the Documents folder.
  final String? dir;
  final bool markdown;

  @override
  State<TextToPdfScreen> createState() => _TextToPdfScreenState();
}

class _TextToPdfScreenState extends State<TextToPdfScreen> {
  final _service = TextPdfService(FileService());
  late final TextEditingController _text = TextEditingController(text: widget.initialText);
  late final TextEditingController _name = TextEditingController(text: widget.name);

  late bool _markdown = widget.markdown;
  TextPageSize _size = TextPageSize.a4;
  bool _landscape = false;
  double _fontSize = 12;
  bool _busy = false;
  String? _nameError;
  String? _error;
  String? _saved;
  int _skipped = 0;

  String get _dir => widget.dir ?? '${FileService.rootPath}/Documents';

  String _savedText(String path) {
    final name = path.split('/').last;
    if (_skipped == 0) return 'Saved as $name';
    return 'Saved as $name\n$_skipped characters could not be drawn and show as "?"';
  }

  @override
  void dispose() {
    _text.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (_text.text.trim().isEmpty) {
      setState(() => _error = 'Type or paste some text first');
      return;
    }
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

    TextPdfResult? result;
    String? error;
    try {
      result = await runWithProgress(context, 'Creating PDF…', () async {
        await Directory(_dir).create(recursive: true);
        return _service.create(
          text: _text.text,
          markdown: _markdown,
          size: _size,
          landscape: _landscape,
          fontSize: _fontSize,
          dir: _dir,
          fileName: '$name.pdf',
        );
      });
    } catch (e) {
      error = e is FormatException ? e.message : "Couldn't create the PDF";
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _saved = result?.path;
      _skipped = result?.skipped ?? 0;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.titleSmall;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 12);
    final saved = _saved;
    final locked = _busy || saved != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Text to PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (saved != null) ...[
            SavedBanner(text: _savedText(saved)),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _text,
            enabled: !locked,
            minLines: 8,
            maxLines: 14,
            decoration: InputDecoration(
              hintText: 'Type or paste your text here',
              filled: true,
              fillColor: scheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Markdown'),
            subtitle: const Text('Headings, lists, bold, italic, code and quotes'),
            value: _markdown,
            onChanged: locked ? null : (v) => setState(() => _markdown = v),
          ),
          const SizedBox(height: 8),
          Text('Page size', style: titleStyle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final s in TextPageSize.values)
                ChoiceChip(
                  label: Text(s.label),
                  selected: _size == s,
                  onSelected: locked ? null : (_) => setState(() => _size = s),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Portrait')),
              ButtonSegment(value: true, label: Text('Landscape')),
            ],
            selected: {_landscape},
            onSelectionChanged: locked ? null : (s) => setState(() => _landscape = s.first),
          ),
          const SizedBox(height: 16),
          Text('Text size', style: titleStyle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final s in const [10.0, 12.0, 14.0, 16.0])
                ChoiceChip(
                  label: Text('${s.round()}'),
                  selected: _fontSize == s,
                  onSelected: locked ? null : (_) => setState(() => _fontSize = s),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            enabled: !locked,
            decoration: InputDecoration(
              labelText: 'File name',
              suffixText: '.pdf',
              helperText: 'Saved in ${_dir.substring(FileService.rootPath.length + 1)}',
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
          const SizedBox(height: 12),
          Text(
            'Works best with English and other Latin-alphabet text. '
                'Other scripts (such as Hindi, Chinese or emoji) can\'t be drawn yet.',
            style: muted,
          ),
        ],
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
              : SavedActions(openPath: saved),
        ),
      ),
    );
  }
}