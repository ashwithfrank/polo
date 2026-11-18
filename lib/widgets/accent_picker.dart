import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

/// Round colour choices for the app's accent, plus a custom one.
class AccentPicker extends StatelessWidget {
  const AccentPicker({super.key, required this.controller});

  final ThemeController controller;

  bool _same(Color a, Color b) => a.toARGB32() == b.toARGB32();

  Future<void> _custom(BuildContext context) async {
    final color = await showDialog<Color>(
      context: context,
      builder: (_) => _CustomColorDialog(initial: controller.accent),
    );
    if (color != null) controller.setAccent(color);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = controller.accent;
    final isPreset = AccentPreset.presets.any((p) => _same(p.color, current));

    Widget swatch({
      required Color color,
      required bool selected,
      required VoidCallback onTap,
      required String label,
      Widget? child,
    }) {
      return Semantics(
        label: label,
        selected: selected,
        button: true,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.15),
                width: selected ? 3 : 1,
              ),
            ),
            child: selected
                ? Icon(
              Icons.check,
              color: ThemeData.estimateBrightnessForColor(color) == Brightness.dark
                  ? Colors.white
                  : Colors.black,
            )
                : child,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final p in AccentPreset.presets)
            swatch(
              color: p.color,
              label: p.name,
              selected: _same(p.color, current),
              onTap: () => controller.setAccent(p.color),
            ),
          swatch(
            color: isPreset ? scheme.surfaceContainerHighest : current,
            label: 'Custom colour',
            selected: !isPreset,
            onTap: () => _custom(context),
            child: const Icon(Icons.palette_outlined, size: 22),
          ),
        ],
      ),
    );
  }
}

/// Pick any colour with three sliders. Owns its state, so nothing outlives it.
class _CustomColorDialog extends StatefulWidget {
  const _CustomColorDialog({required this.initial});

  final Color initial;

  @override
  State<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends State<_CustomColorDialog> {
  late double _hue;
  late double _saturation;
  late double _lightness;

  @override
  void initState() {
    super.initState();
    final hsl = HSLColor.fromColor(widget.initial);
    _hue = hsl.hue;
    _saturation = hsl.saturation;
    _lightness = hsl.lightness.clamp(0.25, 0.7);
  }

  Color get _color => HSLColor.fromAHSL(1, _hue, _saturation, _lightness).toColor();

  String get _hex =>
      '#${(_color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom colour'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 56,
            decoration: BoxDecoration(color: _color, borderRadius: BorderRadius.circular(16)),
            alignment: Alignment.center,
            child: Text(
              _hex,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: ThemeData.estimateBrightnessForColor(_color) == Brightness.dark
                    ? Colors.white
                    : Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _slider('Colour', _hue, 360, (v) => setState(() => _hue = v)),
          _slider('Strength', _saturation, 1, (v) => setState(() => _saturation = v)),
          _slider('Brightness', _lightness, 1, (v) => setState(() => _lightness = v), min: 0.25, max: 0.7),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _color), child: const Text('Use')),
      ],
    );
  }

  Widget _slider(
      String label,
      double value,
      double top,
      ValueChanged<double> onChanged, {
        double min = 0,
        double? max,
      }) {
    return Row(
      children: [
        SizedBox(width: 82, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(
          child: Slider(value: value.clamp(min, max ?? top), min: min, max: max ?? top, onChanged: onChanged),
        ),
      ],
    );
  }
}