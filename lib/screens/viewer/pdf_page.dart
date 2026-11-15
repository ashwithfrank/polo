import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../models/file_item.dart';

class PdfPage extends StatefulWidget {
  const PdfPage({super.key, required this.item});

  final FileItem item;

  @override
  State<PdfPage> createState() => _PdfPageState();
}

class _PdfPageState extends State<PdfPage> {
  final _controller = PdfViewerController();
  int _page = 1;
  int _count = 0;

  Future<String?> _askPassword() async {
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _PromptDialog(
        title: 'Password needed',
        hint: 'Password',
        confirmLabel: 'Open',
        obscure: true,
      ),
    );
  }

  Future<void> _jumpToPage() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _PromptDialog(
        title: 'Go to page',
        hint: '1 to $_count',
        confirmLabel: 'Go',
        number: true,
      ),
    );
    final n = int.tryParse(text?.trim() ?? '');
    if (n == null || _count == 0) return;
    await _controller.goToPage(pageNumber: n.clamp(1, _count));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Stack(
      children: [
        PdfViewer.file(
          widget.item.path,
          controller: _controller,
          passwordProvider: _askPassword,
          params: PdfViewerParams(
            backgroundColor: scheme.surfaceContainerHighest,
            onViewerReady: (document, controller) {
              if (mounted) setState(() => _count = document.pages.length);
            },
            onPageChanged: (page) {
              if (page != null && mounted) setState(() => _page = page);
            },
          ),
        ),
        if (_count > 0)
          Positioned(
            bottom: 16 + bottom,
            left: 0,
            right: 0,
            child: Center(
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _jumpToPage,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      '$_page / $_count',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A one-line text prompt. It owns its controller, so the controller lives as
/// long as the dialog does, including while it fades out.
class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.hint,
    required this.confirmLabel,
    this.obscure = false,
    this.number = false,
  });

  final String title;
  final String hint;
  final String confirmLabel;
  final bool obscure;
  final bool number;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: widget.obscure,
        keyboardType: widget.number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}