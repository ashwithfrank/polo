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

/// Lets any screen ask the main window to show a folder in Browse.
class FolderJump {
  FolderJump._();

  static final ValueNotifier<String?> request = ValueNotifier<String?>(null);

  /// Closes everything above the main window and shows [path] in Browse.
  static void show(BuildContext context, String path) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    request.value = path;
  }
}

/// Bottom buttons after a tool finishes: Done, Folder, and Open when there is a file.
class SavedActions extends StatelessWidget {
  const SavedActions({super.key, this.openPath, this.folderPath});

  /// The file to open, or null when the result is a folder.
  final String? openPath;

  /// The folder to show. Defaults to the folder of [openPath].
  final String? folderPath;

  @override
  Widget build(BuildContext context) {
    final path = openPath;
    final folder = folderPath ??
        (path != null && path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : null);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ),
        if (folder != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => FolderJump.show(context, folder),
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('Folder'),
            ),
          ),
        ],
        if (path != null) ...[
          const SizedBox(width: 8),
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
