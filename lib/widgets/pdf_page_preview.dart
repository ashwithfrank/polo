import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import '../services/pdf_tools_service.dart';

/// One page to show in the preview: its 1-based number and any quarter turns.
class PdfPageRef {
  const PdfPageRef(this.page, {this.turns = 0});

  final int page;
  final int turns;
}

/// Shows [pages] of [doc] big, one at a time, with zoom and next/previous
/// buttons. Starts at position [start] in [pages].
Future<void> showPdfPagePreview(
  BuildContext context, {
  required pdfrx.PdfDocument doc,
  required List<PdfPageRef> pages,
  int start = 0,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _PreviewDialog(doc: doc, pages: pages, start: start),
  );
}

class _PreviewDialog extends StatefulWidget {
  const _PreviewDialog({required this.doc, required this.pages, required this.start});

  final pdfrx.PdfDocument doc;
  final List<PdfPageRef> pages;
  final int start;

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  late int _at = widget.start.clamp(0, widget.pages.length - 1);
  final Map<int, Future<Uint8List>> _images = {};

  Future<Uint8List> _image(int page) {
    return _images.putIfAbsent(
      page,
      () => PdfToolsService.renderPng(widget.doc.pages[page - 1], 2.0),
    );
  }

  void _go(int to) {
    if (to < 0 || to >= widget.pages.length) return;
    setState(() => _at = to);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ref = widget.pages[_at];
    final many = widget.pages.length > 1;

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      many ? 'Page ${ref.page}  ·  ${_at + 1} of ${widget.pages.length}' : 'Page ${ref.page}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.58,
              child: Container(
                width: double.infinity,
                height: double.infinity,
                color: scheme.surfaceContainerHighest,
                child: FutureBuilder<Uint8List>(
                  key: ValueKey(ref.page),
                  future: _image(ref.page),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return const Center(child: Text("Couldn't draw this page"));
                    }
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return InteractiveViewer(
                      minScale: 1,
                      maxScale: 5,
                      child: SizedBox.expand(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: RotatedBox(
                            quarterTurns: ref.turns % 4,
                            child: Image.memory(
                              snap.data!,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.contain,
                              alignment: Alignment.center,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (many)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Previous',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _at > 0 ? () => _go(_at - 1) : null,
                    ),
                    const SizedBox(width: 24),
                    IconButton(
                      tooltip: 'Next',
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _at < widget.pages.length - 1 ? () => _go(_at + 1) : null,
                    ),
                  ],
                ),
              )
            else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
