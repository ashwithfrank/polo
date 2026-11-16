import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Shows a small blocking "working" dialog while [task] runs, then closes it
/// and returns the task's result. [detail] can show a second line that the
/// task updates as it goes, such as "2 of 5 · photo.jpg".
Future<T> runWithProgress<T>(
    BuildContext context,
    String label,
    Future<T> Function() task, {
      ValueListenable<String>? detail,
    }) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 20),
            Expanded(child: _ProgressBody(label: label, detail: detail)),
          ],
        ),
      ),
    ),
  );

  try {
    return await task();
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

/// The text next to the spinner. After a few seconds it adds a reminder that
/// the job is still running, so a long one doesn't look frozen.
class _ProgressBody extends StatefulWidget {
  const _ProgressBody({required this.label, this.detail});

  final String label;
  final ValueListenable<String>? detail;

  @override
  State<_ProgressBody> createState() => _ProgressBodyState();
}

class _ProgressBodyState extends State<_ProgressBody> {
  Timer? _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
    );
    final detail = widget.detail;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label),
        if (detail != null)
          ValueListenableBuilder<String>(
            valueListenable: detail,
            builder: (context, text, _) => text.isEmpty
                ? const SizedBox.shrink()
                : Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: muted),
            ),
          ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topLeft,
          child: _slow
              ? Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Still working. Big files take a while.', style: muted),
          )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}