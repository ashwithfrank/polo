import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/polo_message.dart';

/// Reads "#FF8800", "f80", "rgb(255, 136, 0)", "255 136 0" or "hsl(32, 100%, 50%)".
Color? parseColor(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return null;

  var m = RegExp(r'^#?([0-9a-f]{6}|[0-9a-f]{3})$').firstMatch(s);
  if (m != null) {
    var h = m[1]!;
    if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
    return Color(0xFF000000 | int.parse(h, radix: 16));
  }

  m = RegExp(r'^(?:rgb\()?\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*\)?$')
      .firstMatch(s);
  if (m != null) {
    final r = int.parse(m[1]!), g = int.parse(m[2]!), b = int.parse(m[3]!);
    if (r > 255 || g > 255 || b > 255) return null;
    return Color.fromARGB(255, r, g, b);
  }

  m = RegExp(
    r'^hsl\(?\s*(\d{1,3}(?:\.\d+)?)\s*[, ]\s*(\d{1,3}(?:\.\d+)?)%?\s*[, ]\s*(\d{1,3}(?:\.\d+)?)%?\s*\)?$',
  ).firstMatch(s);
  if (m != null) {
    final h = double.parse(m[1]!) % 360;
    final sat = (double.parse(m[2]!) / 100).clamp(0.0, 1.0);
    final l = (double.parse(m[3]!) / 100).clamp(0.0, 1.0);
    return HSLColor.fromAHSL(1, h, sat, l).toColor();
  }
  return null;
}

int _ch(double v) => (v * 255).round().clamp(0, 255);

String hexOf(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

class ColorScreen extends StatefulWidget {
  const ColorScreen({super.key});

  @override
  State<ColorScreen> createState() => _ColorScreenState();
}

class _ColorScreenState extends State<ColorScreen> {
  final _color = TextEditingController(text: '#FF8800');
  final _background = TextEditingController(text: '#FFFFFF');

  @override
  void dispose() {
    _color.dispose();
    _background.dispose();
    super.dispose();
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    showPoloMessage(context, 'Copied $value');
  }

  InputDecoration _decoration(ColorScheme scheme, String label, bool invalid) {
    return InputDecoration(
      labelText: label,
      hintText: '#FF8800, rgb(255,136,0) or hsl(32,100%,50%)',
      errorText: invalid ? "Couldn't read that colour" : null,
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );

  Widget _valueRow(String label, String value) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(value, style: const TextStyle(fontFamily: 'monospace')),
      subtitle: Text(label),
      trailing: IconButton(
        tooltip: 'Copy',
        icon: const Icon(Icons.copy, size: 20),
        onPressed: () => _copy(value),
      ),
      onTap: () => _copy(value),
    );
  }

  Widget _swatch(Color c) {
    final hex = hexOf(c);
    final light = c.computeLuminance() > 0.5;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _copy(hex),
      child: Container(
        width: 72,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
        ),
        child: Text(
          hex.substring(1),
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            color: light ? Colors.black87 : Colors.white,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = parseColor(_color.text);
    final background = parseColor(_background.text);

    return Scaffold(
      appBar: AppBar(title: const Text('Color tools')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _color,
            autocorrect: false,
            enableSuggestions: false,
            decoration: _decoration(scheme, 'Colour', color == null && _color.text.isNotEmpty),
            onChanged: (_) => setState(() {}),
          ),
          if (color != null) ...[
            const SizedBox(height: 16),
            Container(
              height: 88,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
              ),
            ),
            _heading(context, 'Values (tap to copy)'),
            _valueRow('HEX', hexOf(color)),
            _valueRow('RGB', 'rgb(${_ch(color.r)}, ${_ch(color.g)}, ${_ch(color.b)})'),
            Builder(builder: (_) {
              final hsl = HSLColor.fromColor(color);
              return _valueRow(
                'HSL',
                'hsl(${hsl.hue.round()}, ${(hsl.saturation * 100).round()}%, '
                    '${(hsl.lightness * 100).round()}%)',
              );
            }),
            _heading(context, 'Lighter'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in const [0.2, 0.4, 0.6, 0.8])
                  _swatch(Color.lerp(color, Colors.white, t)!),
              ],
            ),
            _heading(context, 'Darker'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in const [0.2, 0.4, 0.6, 0.8])
                  _swatch(Color.lerp(color, Colors.black, t)!),
              ],
            ),
            _heading(context, 'Contrast checker'),
            TextField(
              controller: _background,
              autocorrect: false,
              enableSuggestions: false,
              decoration: _decoration(
                scheme,
                'Background colour',
                background == null && _background.text.isNotEmpty,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (background != null) ...[
              const SizedBox(height: 12),
              _ContrastResult(foreground: color, background: background),
            ],
          ],
        ],
      ),
    );
  }
}

class _ContrastResult extends StatelessWidget {
  const _ContrastResult({required this.foreground, required this.background});

  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final a = foreground.computeLuminance();
    final b = background.computeLuminance();
    final ratio = (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);

    Widget check(String label, bool pass) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            pass ? Icons.check_circle : Icons.cancel,
            size: 18,
            color: pass ? Colors.green : Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          ),
          child: Text(
            'Sample text Aa',
            style: TextStyle(color: foreground, fontSize: 20, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Contrast ratio ${ratio.toStringAsFixed(2)} : 1',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        check('AA, normal text (4.5)', ratio >= 4.5),
        check('AA, large text (3)', ratio >= 3),
        check('AAA, normal text (7)', ratio >= 7),
        check('AAA, large text (4.5)', ratio >= 4.5),
      ],
    );
  }
}