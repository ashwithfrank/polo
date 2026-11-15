import 'package:flutter/material.dart';

class RegexScreen extends StatefulWidget {
  const RegexScreen({super.key});

  @override
  State<RegexScreen> createState() => _RegexScreenState();
}

class _RegexScreenState extends State<RegexScreen> {
  final _pattern = TextEditingController();
  final _text = TextEditingController();
  bool _ignoreCase = false;
  bool _multiLine = false;
  bool _dotAll = false;

  @override
  void dispose() {
    _pattern.dispose();
    _text.dispose();
    super.dispose();
  }

  InputDecoration _decoration(ColorScheme scheme, String hint, {String? error}) {
    return InputDecoration(
      hintText: hint,
      errorText: error,
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 14);

    RegExp? regex;
    String? error;
    if (_pattern.text.isNotEmpty) {
      try {
        regex = RegExp(
          _pattern.text,
          caseSensitive: !_ignoreCase,
          multiLine: _multiLine,
          dotAll: _dotAll,
        );
      } on FormatException catch (e) {
        error = e.message;
      }
    }

    final text = _text.text;
    final matches = regex == null || text.isEmpty
        ? const <RegExpMatch>[]
        : regex.allMatches(text).take(500).toList();

    // The test text with every match highlighted.
    final spans = <InlineSpan>[];
    var at = 0;
    for (final m in matches) {
      if (m.end == m.start || m.start < at) continue;
      if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
      spans.add(
        TextSpan(
          text: text.substring(m.start, m.end),
          style: TextStyle(
            backgroundColor: scheme.primaryContainer,
            color: scheme.onPrimaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));

    return Scaffold(
      appBar: AppBar(title: const Text('Regex tester')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _pattern,
            autocorrect: false,
            enableSuggestions: false,
            style: mono,
            decoration: _decoration(scheme, 'Pattern, e.g. \\d{3}-\\d{4}', error: error),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Ignore case'),
                selected: _ignoreCase,
                onSelected: (v) => setState(() => _ignoreCase = v),
              ),
              FilterChip(
                label: const Text('Multi-line'),
                selected: _multiLine,
                onSelected: (v) => setState(() => _multiLine = v),
              ),
              FilterChip(
                label: const Text('Dot matches newline'),
                selected: _dotAll,
                onSelected: (v) => setState(() => _dotAll = v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 10,
            autocorrect: false,
            enableSuggestions: false,
            style: mono,
            decoration: _decoration(scheme, 'Text to test'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Text(
            regex == null || text.isEmpty
                ? 'Matches'
                : matches.isEmpty
                ? 'No matches'
                : '${matches.length}${matches.length == 500 ? '+' : ''} '
                '${matches.length == 1 ? 'match' : 'matches'}',
            style: TextStyle(fontWeight: FontWeight.w600, color: scheme.primary),
          ),
          const SizedBox(height: 8),
          if (spans.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: SelectableText.rich(
                TextSpan(style: mono.copyWith(color: scheme.onSurface), children: spans),
              ),
            ),
          const SizedBox(height: 8),
          for (var i = 0; i < matches.length && i < 50; i++)
            _MatchTile(index: i + 1, match: matches[i]),
          if (matches.length > 50)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Showing the first 50 matches',
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
              ),
            ),
        ],
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.index, required this.match});

  final int index;
  final RegExpMatch match;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.6));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '#$index  ', style: muted),
                TextSpan(
                  text: match.group(0)!.isEmpty ? '(empty)' : match.group(0),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                TextSpan(text: '   at ${match.start}-${match.end}', style: muted),
              ],
            ),
          ),
          for (var g = 1; g <= match.groupCount; g++)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 2),
              child: Text(
                'Group $g: ${match.group(g) ?? '(no match)'}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}