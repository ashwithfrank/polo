import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/polo_message.dart';

/// One way a text tool can transform its input.
class TextMode {
  const TextMode(
      this.label,
      this.run, {
        this.hint = 'Type or paste here',
        this.emptyRuns = false,
      });

  final String label;
  final String Function(String input) run;
  final String hint;

  /// Run even when the input is empty (e.g. "current time").
  final bool emptyRuns;
}

/// A simple input -> output screen shared by the text-based tools. The result
/// updates as you type. Nothing leaves the device.
class TextToolScreen extends StatefulWidget {
  const TextToolScreen({super.key, required this.title, required this.modes});

  final String title;
  final List<TextMode> modes;

  @override
  State<TextToolScreen> createState() => _TextToolScreenState();
}

class _TextToolScreenState extends State<TextToolScreen> {
  final _input = TextEditingController();
  int _mode = 0;
  String _output = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _recompute() {
    final mode = widget.modes[_mode];
    final text = _input.text;
    if (text.trim().isEmpty && !mode.emptyRuns) {
      _output = '';
      _error = null;
      return;
    }
    try {
      _output = mode.run(text);
      _error = null;
    } on FormatException catch (e) {
      _output = '';
      _error = e.message;
    } catch (_) {
      _output = '';
      _error = "Couldn't convert that";
    }
  }

  void _toast(String message) {
    showPoloMessage(context, message);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      _toast('Nothing to paste');
      return;
    }
    _input.text = text;
    setState(_recompute);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _output));
    if (mounted) _toast('Copied');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mode = widget.modes[_mode];

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.modes.length > 1) ...[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var i = 0; i < widget.modes.length; i++)
                  ChoiceChip(
                    label: Text(widget.modes[i].label),
                    selected: _mode == i,
                    onSelected: (_) => setState(() {
                      _mode = i;
                      _recompute();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _input,
            minLines: 4,
            maxLines: 10,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            decoration: InputDecoration(
              hintText: mode.hint,
              filled: true,
              fillColor: scheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (_) => setState(_recompute),
          ),
          Row(
            children: [
              TextButton.icon(
                onPressed: _paste,
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('Paste'),
              ),
              TextButton.icon(
                onPressed: _input.text.isEmpty
                    ? null
                    : () {
                  _input.clear();
                  setState(_recompute);
                },
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Result',
                style: TextStyle(fontWeight: FontWeight.w600, color: scheme.primary),
              ),
              const Spacer(),
              if (_output.isNotEmpty) ...[
                TextButton.icon(
                  onPressed: () {
                    _input.text = _output;
                    setState(_recompute);
                  },
                  icon: const Icon(Icons.swap_vert, size: 18),
                  label: const Text('Use as input'),
                ),
                TextButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy'),
                ),
              ],
            ],
          ),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 96),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: _error != null
                ? Text(_error!, style: TextStyle(color: scheme.error))
                : SelectableText(
              _output.isEmpty ? 'The result appears here' : _output,
              style: TextStyle(
                fontFamily: _output.isEmpty ? null : 'monospace',
                fontSize: 14,
                color: _output.isEmpty
                    ? scheme.onSurface.withValues(alpha: 0.5)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}