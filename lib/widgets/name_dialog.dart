import 'package:flutter/material.dart';

/// Asks for a file or folder name. Pops with the trimmed name, or null.
class NameDialog extends StatefulWidget {
  const NameDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    required this.existing,
    this.initial = '',
    this.hint,
    this.suffix,
  });

  final String title;
  final String confirmLabel;
  final String initial;
  final String? hint;
  final String? suffix;

  /// Names that can't be used.
  final Set<String> existing;

  @override
  State<NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<NameDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    String? error;
    if (name.isEmpty) {
      error = 'Enter a name';
    } else if (name.contains('/')) {
      error = "Names can't contain /";
    } else if (widget.existing.contains(name)) {
      error = "That name's already taken";
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: widget.hint,
          suffixText: widget.suffix,
          errorText: _error,
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}