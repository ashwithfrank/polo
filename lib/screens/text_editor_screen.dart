import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/file_item.dart';
import '../widgets/name_dialog.dart';
import '../widgets/polo_message.dart';

/// Biggest file Polo edits. Bigger ones are only viewed, because a text box
/// with hundreds of thousands of lines gets slow.
const _maxEditBytes = 500 * 1024;

const _editorStyle = TextStyle(fontFamily: 'monospace', fontSize: 14, height: 1.4);

enum _Leave { save, discard, cancel }

/// Edits a text file: type, undo, find and replace, save or save a copy.
/// The file is only changed when you choose to save.
class TextEditorScreen extends StatefulWidget {
  const TextEditorScreen({super.key, required this.item});

  final FileItem item;

  @override
  State<TextEditorScreen> createState() => _TextEditorScreenState();
}

class _TextEditorScreenState extends State<TextEditorScreen> {
  final _controller = TextEditingController();
  final _undo = UndoHistoryController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final _findFocus = FocusNode();
  final _find = TextEditingController();
  final _replace = TextEditingController();

  bool _loading = true;
  String? _loadError;

  String _original = '';
  bool _dirty = false;
  bool _saving = false;
  bool _confirmedOverwrite = false;

  // How the file was written, so it is saved the same way.
  bool _crlf = false;
  bool _bom = false;
  bool _latin1 = false;

  // Counts shown at the bottom.
  int _words = 0;
  int _lines = 1;
  Timer? _countTimer;

  // Find and replace.
  bool _showFind = false;
  bool _caseSensitive = false;
  List<Match> _matches = const [];
  int _matchIndex = -1;
  double _editorWidth = 300;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    _load();
  }

  @override
  void dispose() {
    _countTimer?.cancel();
    _controller.dispose();
    _undo.dispose();
    _scroll.dispose();
    _focus.dispose();
    _findFocus.dispose();
    _find.dispose();
    _replace.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final file = File(widget.item.path);
      final length = await file.length();
      if (length > _maxEditBytes) {
        throw FormatException(
          'This file is too big to edit in Polo (the limit is ${_maxEditBytes ~/ 1024} KB). '
              'You can still view it.',
        );
      }
      var bytes = await file.readAsBytes();
      final probe = bytes.length < 4096 ? bytes : bytes.sublist(0, 4096);
      if (probe.contains(0)) throw const FormatException("This file isn't plain text");

      if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
        _bom = true;
        bytes = bytes.sublist(3);
      }
      String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        text = latin1.decode(bytes);
        _latin1 = true;
      }
      if (text.contains('\r\n')) {
        _crlf = true;
        text = text.replaceAll('\r\n', '\n');
      }

      _original = text;
      _controller.text = text;
      _recount();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e is FormatException ? e.message : "Couldn't open this file";
      });
    }
  }

  void _onChanged() {
    final dirty = _controller.text != _original;
    if (dirty != _dirty) setState(() => _dirty = dirty);
    _countTimer?.cancel();
    _countTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(_recount);
    });
  }

  void _recount() {
    final text = _controller.text;
    _words = RegExp(r'\S+').allMatches(text).length;
    _lines = '\n'.allMatches(text).length + 1;
  }

  // ---- Saving -----------------------------------------------------------------

  Uint8List _encode(String text, {required bool allowLatin1}) {
    var out = text;
    if (_crlf) out = out.replaceAll('\n', '\r\n');
    List<int> body;
    if (_latin1 && allowLatin1) {
      body = latin1.encode(out); // throws if a character doesn't fit
    } else {
      body = utf8.encode(out);
    }
    return Uint8List.fromList([if (_bom && !(_latin1 && allowLatin1)) ...[0xEF, 0xBB, 0xBF], ...body]);
  }

  /// Writes the text to [path], through a temporary file so a failure can't
  /// leave a half-written file behind.
  Future<void> _write(String path) async {
    Uint8List bytes;
    try {
      bytes = _encode(_controller.text, allowLatin1: true);
    } on ArgumentError {
      // The text has characters the file's old encoding can't hold.
      bytes = _encode(_controller.text, allowLatin1: false);
      _latin1 = false;
      if (mounted) showPoloMessage(context, 'Saved as UTF-8 because of new characters');
    }
    final temp = File('$path.polo_tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(path);
  }

  Future<bool> _save() async {
    if (_saving) return false;

    if (!_confirmedOverwrite) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Save changes?'),
          content: Text('This replaces ${widget.item.name} with your edited version.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(context, 'copy'),
              child: const Text('Save as copy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return false;
      if (choice == 'copy') return _saveCopy();
      _confirmedOverwrite = true;
    }

    setState(() => _saving = true);
    try {
      await _write(widget.item.path);
      if (!mounted) return true;
      setState(() {
        _original = _controller.text;
        _dirty = false;
      });
      showPoloMessage(context, 'Saved');
      return true;
    } catch (_) {
      if (mounted) showPoloMessage(context, "Couldn't save. The file may be read-only");
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _saveCopy() async {
    final item = widget.item;
    final dot = item.name.lastIndexOf('.');
    final suggestion = dot > 0
        ? '${item.name.substring(0, dot)} (edited)${item.name.substring(dot)}'
        : '${item.name} (edited)';

    Set<String> existing = {};
    try {
      existing = {
        for (final e in Directory(item.parentPath).listSync()) e.path.split('/').last,
      };
    } catch (_) {}
    if (!mounted) return false;

    final name = await showDialog<String>(
      context: context,
      builder: (_) => NameDialog(
        title: 'Save as a copy',
        confirmLabel: 'Save',
        initial: suggestion,
        hint: 'File name',
        existing: existing,
      ),
    );
    if (name == null || !mounted) return false;

    try {
      await _write('${item.parentPath}/$name');
      if (mounted) showPoloMessage(context, 'Saved as $name');
      return true;
    } catch (_) {
      if (mounted) showPoloMessage(context, "Couldn't save the copy");
      return false;
    }
  }

  /// Back button: ask what to do with unsaved changes.
  Future<void> _onBack() async {
    final leave = await showDialog<_Leave>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('You have changes that are not saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _Leave.cancel),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _Leave.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _Leave.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (leave == _Leave.discard) {
      Navigator.pop(context, false);
    } else if (leave == _Leave.save) {
      if (await _save() && mounted) Navigator.pop(context, true);
    }
  }

  // ---- Find and replace ---------------------------------------------------------

  RegExp? get _pattern {
    final q = _find.text;
    if (q.isEmpty) return null;
    return RegExp(RegExp.escape(q), caseSensitive: _caseSensitive);
  }

  void _search() {
    final re = _pattern;
    setState(() {
      _matches = re == null ? const [] : re.allMatches(_controller.text).take(5000).toList();
      if (_matches.isEmpty) {
        _matchIndex = -1;
      } else if (_matchIndex >= _matches.length || _matchIndex < 0) {
        _matchIndex = 0;
      }
    });
  }

  void _step(int direction) {
    _search();
    if (_matches.isEmpty) {
      showPoloMessage(context, 'No matches');
      return;
    }
    // Carry on from the cursor so Next goes to the next match after it.
    final cursor = _controller.selection.isValid ? _controller.selection.end : 0;
    var index = _matchIndex;
    if (direction > 0) {
      index = _matches.indexWhere((m) => m.start >= cursor);
      if (index < 0) index = 0;
    } else {
      final start = _controller.selection.isValid ? _controller.selection.start : 0;
      index = _matches.lastIndexWhere((m) => m.end <= start);
      if (index < 0) index = _matches.length - 1;
    }
    _select(index);
  }

  void _select(int index) {
    final m = _matches[index];
    setState(() => _matchIndex = index);
    _focus.requestFocus();
    _controller.selection = TextSelection(baseOffset: m.start, extentOffset: m.end);
    _scrollTo(m.start);
  }

  /// Scrolls so the character at [offset] is near the top of the editor.
  void _scrollTo(int offset) {
    final painter = TextPainter(
      text: TextSpan(text: _controller.text, style: _editorStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _editorWidth);
    final y = painter.getOffsetForCaret(TextPosition(offset: offset), Rect.zero).dy;
    painter.dispose();
    if (!_scroll.hasClients) return;
    final target = (y - 60).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  void _replaceOne() {
    final sel = _controller.selection;
    final re = _pattern;
    if (re == null || !sel.isValid || sel.isCollapsed) {
      _step(1);
      return;
    }
    final selected = _controller.text.substring(sel.start, sel.end);
    if (re.matchAsPrefix(selected) == null || selected.length != _find.text.length) {
      _step(1);
      return;
    }
    final text = _controller.text.replaceRange(sel.start, sel.end, _replace.text);
    final caret = sel.start + _replace.text.length;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
    );
    _step(1);
  }

  void _replaceAll() {
    final re = _pattern;
    if (re == null) return;
    final count = re.allMatches(_controller.text).length;
    if (count == 0) {
      showPoloMessage(context, 'No matches');
      return;
    }
    final replacement = _replace.text;
    _controller.value = TextEditingValue(
      text: _controller.text.replaceAllMapped(re, (_) => replacement),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _search();
    showPoloMessage(context, 'Replaced $count ${count == 1 ? 'match' : 'matches'}');
  }

  void _toggleFind() {
    setState(() => _showFind = !_showFind);
    if (_showFind) {
      _findFocus.requestFocus();
    } else {
      _matches = const [];
      _matchIndex = -1;
      _focus.requestFocus();
    }
  }

  // ---- Screen -----------------------------------------------------------------

  Widget _findPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = _matches.isEmpty
        ? (_find.text.isEmpty ? '' : '0')
        : '${_matchIndex + 1}/${_matches.length}';

    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _find,
                    focusNode: _findFocus,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => _search(),
                    onSubmitted: (_) => _step(1),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Find',
                      suffixText: count,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Previous',
                  icon: const Icon(Icons.keyboard_arrow_up),
                  onPressed: () => _step(-1),
                ),
                IconButton(
                  tooltip: 'Next',
                  icon: const Icon(Icons.keyboard_arrow_down),
                  onPressed: () => _step(1),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: _toggleFind,
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replace,
                    decoration: const InputDecoration(isDense: true, hintText: 'Replace with'),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(onPressed: _replaceOne, child: const Text('Replace')),
                TextButton(onPressed: _replaceAll, child: const Text('All')),
                Tooltip(
                  message: 'Match case',
                  child: FilterChip(
                    label: const Text('Aa'),
                    selected: _caseSensitive,
                    showCheckmark: false,
                    onSelected: (v) {
                      setState(() => _caseSensitive = v);
                      _search();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.6));

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${_dirty ? '• ' : ''}${widget.item.name}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16),
          ),
          actions: [
            ValueListenableBuilder<UndoHistoryValue>(
              valueListenable: _undo,
              builder: (_, v, _) => IconButton(
                tooltip: 'Undo',
                icon: const Icon(Icons.undo),
                onPressed: v.canUndo ? _undo.undo : null,
              ),
            ),
            ValueListenableBuilder<UndoHistoryValue>(
              valueListenable: _undo,
              builder: (_, v, _) => IconButton(
                tooltip: 'Redo',
                icon: const Icon(Icons.redo),
                onPressed: v.canRedo ? _undo.redo : null,
              ),
            ),
            IconButton(
              tooltip: 'Find and replace',
              icon: const Icon(Icons.search),
              onPressed: _loading || _loadError != null ? null : _toggleFind,
            ),
            IconButton(
              tooltip: 'Save',
              icon: const Icon(Icons.check),
              onPressed: _dirty && !_saving ? _save : null,
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'copy') _saveCopy();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'copy', child: Text('Save as a copy')),
              ],
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
            ? Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.error),
            ),
          ),
        )
            : Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  _editorWidth = box.maxWidth - 32;
                  return TextField(
                    controller: _controller,
                    focusNode: _focus,
                    undoController: _undo,
                    scrollController: _scroll,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: _editorStyle,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.all(16),
                    ),
                  );
                },
              ),
            ),
            if (_showFind) _findPanel(context),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: scheme.surfaceContainerHighest,
              child: Text(
                '$_words words · ${_controller.text.length} characters · $_lines lines'
                    ' · ${_latin1 ? 'Latin-1' : 'UTF-8'}${_crlf ? ' · CRLF' : ''}',
                style: muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}