import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'wordlist.dart';
import '../widgets/polo_message.dart';

/// Password and passphrase generator. Uses the device's secure random source
/// and never stores or sends what it makes.
class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key});

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final _random = Random.secure();

  bool _passphrase = false;

  // Password options
  double _length = 16;
  bool _upper = true;
  bool _lower = true;
  bool _digits = true;
  bool _symbols = true;
  bool _avoidSimilar = false;

  // Passphrase options
  double _words = 4;
  String _separator = '-';
  bool _capitalize = false;
  bool _addNumber = true;

  String _result = '';
  double _bits = 0;

  static const _upperChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const _lowerChars = 'abcdefghijklmnopqrstuvwxyz';
  static const _digitChars = '0123456789';
  static const _symbolChars = r'!@#$%^&*()-_=+[]{};:,.?';
  static const _similar = '0O1lI|';

  @override
  void initState() {
    super.initState();
    _generate();
  }

  void _generate() {
    if (_passphrase) {
      final n = _words.round();
      final parts = [
        for (var i = 0; i < n; i++)
              () {
            final w = passphraseWords[_random.nextInt(passphraseWords.length)];
            return _capitalize ? '${w[0].toUpperCase()}${w.substring(1)}' : w;
          }(),
      ];
      var text = parts.join(_separator);
      var bits = n * (log(passphraseWords.length) / ln2);
      if (_addNumber) {
        text += '$_separator${_random.nextInt(100)}';
        bits += log(100) / ln2;
      }
      _result = text;
      _bits = bits;
      return;
    }

    String clean(String s) =>
        _avoidSimilar ? s.split('').where((c) => !_similar.contains(c)).join() : s;
    final pools = <String>[
      if (_upper) clean(_upperChars),
      if (_lower) clean(_lowerChars),
      if (_digits) clean(_digitChars),
      if (_symbols) clean(_symbolChars),
    ];
    if (pools.isEmpty) {
      _result = '';
      _bits = 0;
      return;
    }
    final all = pools.join();
    final length = _length.round();
    final chars = <String>[
      for (final p in pools) p[_random.nextInt(p.length)],
    ];
    while (chars.length < length) {
      chars.add(all[_random.nextInt(all.length)]);
    }
    chars.shuffle(_random);
    _result = chars.take(length).join();
    _bits = length * (log(all.length) / ln2);
  }

  String get _strength {
    if (_result.isEmpty) return '';
    if (_bits < 40) return 'Weak';
    if (_bits < 60) return 'Fair';
    if (_bits < 80) return 'Good';
    return 'Strong';
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _result));
    if (!mounted) return;
    showPoloMessage(context, 'Copied');
  }

  void _change(VoidCallback fn) => setState(() {
    fn();
    _generate();
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Password generator')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Password')),
              ButtonSegment(value: true, label: Text('Passphrase')),
            ],
            selected: {_passphrase},
            onSelectionChanged: (s) => _change(() => _passphrase = s.first),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  _result.isEmpty ? 'Pick at least one character type' : _result,
                  style: TextStyle(
                    fontFamily: _result.isEmpty ? null : 'monospace',
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_result.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '$_strength · about ${_bits.round()} bits of randomness',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _result.isEmpty ? null : _copy,
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(_generate),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('New one'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (!_passphrase) ...[
            Text('Length: ${_length.round()}'),
            Slider(
              value: _length,
              min: 8,
              max: 64,
              divisions: 56,
              label: _length.round().toString(),
              onChanged: (v) => _change(() => _length = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Uppercase (A-Z)'),
              value: _upper,
              onChanged: (v) => _change(() => _upper = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Lowercase (a-z)'),
              value: _lower,
              onChanged: (v) => _change(() => _lower = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Numbers (0-9)'),
              value: _digits,
              onChanged: (v) => _change(() => _digits = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Symbols (!@#\$…)'),
              value: _symbols,
              onChanged: (v) => _change(() => _symbols = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Avoid look-alikes'),
              subtitle: const Text('Skips 0 O 1 l I |'),
              value: _avoidSimilar,
              onChanged: (v) => _change(() => _avoidSimilar = v),
            ),
          ] else ...[
            Text('Words: ${_words.round()}'),
            Slider(
              value: _words,
              min: 3,
              max: 8,
              divisions: 5,
              label: _words.round().toString(),
              onChanged: (v) => _change(() => _words = v),
            ),
            const Text('Separator'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final s in const ['-', '.', '_', ' '])
                  ChoiceChip(
                    label: Text(s == ' ' ? 'space' : s),
                    selected: _separator == s,
                    onSelected: (_) => _change(() => _separator = s),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Capitalise words'),
              value: _capitalize,
              onChanged: (v) => _change(() => _capitalize = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Add a number at the end'),
              value: _addNumber,
              onChanged: (v) => _change(() => _addNumber = v),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Made on your device with a secure random source. Polo never saves or sends it.',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}