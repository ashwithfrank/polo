import 'dart:io';

import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../widgets/polo_message.dart';
import '../services/rename_plan.dart';

class BatchRenameScreen extends StatefulWidget {
  const BatchRenameScreen({super.key, required this.items});

  final List<FileItem> items;

  @override
  State<BatchRenameScreen> createState() => _BatchRenameScreenState();
}

class _BatchRenameScreenState extends State<BatchRenameScreen> {
  late final List<FileItem> _items = [...widget.items]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  final _base = TextEditingController();
  final _start = TextEditingController(text: '1');
  final _find = TextEditingController();
  final _replaceWith = TextEditingController();
  final _prefix = TextEditingController();
  final _suffix = TextEditingController();

  RenameMode _mode = RenameMode.numbering;
  CaseStyle _caseStyle = CaseStyle.lower;

  /// Lower-case names already in each folder, from items that are not part of
  /// this batch (their old names are about to be freed).
  Map<String, Set<String>>? _taken;
  bool _running = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTaken();
  }

  @override
  void dispose() {
    for (final c in [_base, _start, _find, _replaceWith, _prefix, _suffix]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadTaken() async {
    final batch = {for (final i in _items) i.path};
    final result = <String, Set<String>>{};
    for (final parent in {for (final i in _items) i.parentPath}) {
      final names = <String>{};
      try {
        await for (final e in Directory(parent).list(followLinks: false)) {
          if (!batch.contains(e.path)) names.add(e.path.split('/').last.toLowerCase());
        }
      } on FileSystemException {
        // Treated as empty; the rename itself reports real problems.
      }
      result[parent] = names;
    }
    if (mounted) setState(() => _taken = result);
  }

  RenameOptions get _options => RenameOptions(
    mode: _mode,
    base: _base.text,
    start: int.tryParse(_start.text.trim()) ?? 1,
    find: _find.text,
    replaceWith: _replaceWith.text,
    prefix: _prefix.text,
    suffix: _suffix.text,
    caseStyle: _caseStyle,
  );

  /// Why the name at [i] can't be used, or null.
  String? _problem(int i, List<String> names) {
    final reason = invalidReason(_items[i], names[i]);
    if (reason != null) return reason;
    final key = names[i].toLowerCase();
    final parent = _items[i].parentPath;
    if (_taken?[parent]?.contains(key) ?? false) return 'A file with this name exists';
    for (var j = 0; j < names.length; j++) {
      if (j != i && _items[j].parentPath == parent && names[j].toLowerCase() == key) {
        return 'Two files would get this name';
      }
    }
    return null;
  }

  Future<void> _apply(List<String> names) async {
    setState(() {
      _running = true;
      _error = null;
    });
    final changed = [
      for (var i = 0; i < _items.length; i++)
        if (_items[i].name != names[i]) i,
    ];
    try {
      await applyRenames(
        [for (final i in changed) _items[i]],
        [for (final i in changed) names[i]],
      );
    } on FileSystemException catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = "Couldn't rename: ${e.osError?.message ?? e.message}. Nothing was changed.";
      });
      return;
    }
    if (!mounted) return;
    // Shown before closing: the message lives above all screens.
    showPoloMessage(
      context,
      'Renamed ${changed.length} ${changed.length == 1 ? 'file' : 'files'}',
    );
    Navigator.pop(context, true);
  }

  Widget _field(TextEditingController c, String label, {bool number = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        enabled: !_running,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = _items.length;

    final options = _options;
    final names = [
      for (var i = 0; i < count; i++) newNameFor(_items[i], i, count, options),
    ];
    final problems = [for (var i = 0; i < count; i++) _problem(i, names)];
    final changed = [
      for (var i = 0; i < count; i++)
        if (names[i] != _items[i].name) i,
    ];
    final problemCount = changed.where((i) => problems[i] != null).length;
    final canApply = _taken != null && !_running && changed.isNotEmpty && problemCount == 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Batch rename')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (mode, label) in const [
                (RenameMode.numbering, 'Name and number'),
                (RenameMode.replace, 'Find and replace'),
                (RenameMode.addText, 'Add text'),
                (RenameMode.changeCase, 'Change case'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _mode == mode,
                  onSelected: _running ? null : (_) => setState(() => _mode = mode),
                ),
            ],
          ),
          const SizedBox(height: 16),
          switch (_mode) {
            RenameMode.numbering => Column(children: [
              _field(_base, 'Name (for example Holiday_)'),
              _field(_start, 'Start at', number: true),
            ]),
            RenameMode.replace => Column(children: [
              _field(_find, 'Find'),
              _field(_replaceWith, 'Replace with'),
            ]),
            RenameMode.addText => Column(children: [
              _field(_prefix, 'Add before the name'),
              _field(_suffix, 'Add after the name'),
            ]),
            RenameMode.changeCase => Wrap(
              spacing: 8,
              children: [
                for (final (style, label) in const [
                  (CaseStyle.lower, 'lowercase'),
                  (CaseStyle.upper, 'UPPERCASE'),
                  (CaseStyle.title, 'Title Case'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _caseStyle == style,
                    onSelected: _running ? null : (_) => setState(() => _caseStyle = style),
                  ),
              ],
            ),
          },
          const SizedBox(height: 8),
          Text(
            'Extensions stay the same.',
            style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('Preview', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              if (problemCount > 0)
                Text(
                  '$problemCount can\'t be renamed',
                  style: TextStyle(color: scheme.error, fontSize: 12),
                ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: scheme.error)),
            ),
          const SizedBox(height: 4),
          for (var i = 0; i < count; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                names[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: problems[i] != null && names[i] != _items[i].name
                      ? scheme.error
                      : null,
                ),
              ),
              subtitle: Text(
                names[i] == _items[i].name
                    ? '${_items[i].name} (no change)'
                    : problems[i] ?? _items[i].name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: problems[i] != null && names[i] != _items[i].name
                      ? scheme.error
                      : scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: canApply ? () => _apply(names) : null,
            child: Text(
              _running
                  ? 'Renaming…'
                  : 'Rename ${changed.length} ${changed.length == 1 ? 'file' : 'files'}',
            ),
          ),
        ),
      ),
    );
  }
}