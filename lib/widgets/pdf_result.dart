import 'package:flutter/material.dart';

import '../models/file_item.dart';
import 'open_file.dart';

/// "Saved as ..." box shown after a tool finishes.
class SavedBanner extends StatelessWidget {
  const SavedBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(color: scheme.onPrimaryContainer)),
          ),
        ],
      ),
    );
  }
}

/// Bottom buttons after a tool finishes: Done, and Open when there is a file.
class SavedActions extends StatelessWidget {
  const SavedActions({super.key, this.openPath});

  /// The file to open, or null when the result is a folder.
  final String? openPath;

  @override
  Widget build(BuildContext context) {
    final path = openPath;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ),
        if (path != null) ...[
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => openFile(
                context,
                FileItem(
                  path: path,
                  name: path.split('/').last,
                  isDirectory: false,
                  size: 0,
                  modified: DateTime.now(),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ],
      ],
    );
  }
}

String baseName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot > 0 ? fileName.substring(0, dot) : fileName;
}