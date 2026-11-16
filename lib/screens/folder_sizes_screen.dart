import 'package:flutter/material.dart';

import '../services/cleanup_service.dart';
import '../services/file_service.dart';
import '../services/storage_access.dart';
import '../utils/format.dart';
import '../widgets/file_actions.dart';
import '../widgets/file_tile.dart';
import '../widgets/message_view.dart';
import '../widgets/open_file.dart';

/// Shows which folders take the most space. Tap a folder to look inside it,
/// long-press anything to move it to the trash.
class FolderSizesScreen extends StatefulWidget {
  const FolderSizesScreen({super.key});

  @override
  State<FolderSizesScreen> createState() => _FolderSizesScreenState();
}

class _FolderSizesScreenState extends State<FolderSizesScreen> {
  bool? _granted;
  bool _loading = true;
  String _path = FileService.rootPath;
  List<SizeEntry> _entries = const [];

  bool get _atRoot => _path == FileService.rootPath;

  String get _label =>
      _atRoot ? 'Internal storage' : _path.substring(FileService.rootPath.length + 1);

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    var ok = await StorageAccess.isGranted();
    if (!ok) ok = await StorageAccess.request();
    if (!mounted) return;
    setState(() => _granted = ok);
    if (ok) await _open(_path);
  }

  Future<void> _open(String path) async {
    setState(() {
      _loading = true;
      _path = path;
    });
    final entries = await CleanupService.folderSizes(path);
    if (!mounted || _path != path) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  void _up() {
    if (_atRoot) return;
    _open(_path.substring(0, _path.lastIndexOf('/')));
  }

  Future<void> _delete(SizeEntry e) async {
    final moved = await trashFiles(context, [e.item]);
    if (moved.isNotEmpty && mounted) await _open(_path);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = _entries.fold<int>(0, (sum, e) => sum + e.bytes);
    final largest = _entries.isEmpty ? 1 : _entries.first.bytes.clamp(1, 1 << 62);

    return PopScope(
      canPop: _atRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _up();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Folder sizes')),
        body: _granted == false
            ? MessageView(
          icon: Icons.folder_special_outlined,
          title: 'Allow access to your files',
          body: 'Polo needs permission to measure your folders.',
          actionLabel: 'Grant access',
          onAction: _start,
        )
            : Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  if (!_atRoot)
                    IconButton(
                      tooltip: 'Up',
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: _up,
                    ),
                  Expanded(
                    child: Text(
                      _label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (!_loading)
                    Text(
                      formatBytes(total),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _entries.isEmpty
                  ? const MessageView(
                icon: Icons.folder_open_outlined,
                title: 'Nothing here',
                body: 'This folder is empty or can\'t be read.',
              )
                  : ListView.builder(
                itemCount: _entries.length,
                itemBuilder: (context, i) {
                  final e = _entries[i];
                  final (icon, color) = fileIconFor(e.item.kind, scheme);
                  return ListTile(
                    onTap: () async {
                      if (e.item.isDirectory) {
                        _open(e.item.path);
                      } else {
                        final gone = await openFile(context, e.item);
                        if (gone.isNotEmpty && mounted) _open(_path);
                      }
                    },
                    onLongPress: () => _delete(e),
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 22),
                    ),
                    title: Text(
                      e.item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: e.bytes / largest,
                            minHeight: 5,
                            backgroundColor: scheme.surfaceContainerHighest,
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          e.item.isDirectory
                              ? '${e.files} ${e.files == 1 ? 'file' : 'files'}'
                              : e.item.dateLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                    trailing: Text(
                      formatBytes(e.bytes),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Tap a folder to look inside. Long-press to move to trash.',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}