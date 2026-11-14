import 'package:flutter/material.dart';

/// Shows a small blocking "working" dialog while [task] runs, then closes it
/// and returns the task's result.
Future<T> runWithProgress<T>(
    BuildContext context,
    String label,
    Future<T> Function() task,
    ) async {
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
            Expanded(child: Text(label)),
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