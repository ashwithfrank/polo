import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/file_item.dart';
import '../services/checksum_service.dart';
import '../services/file_service.dart';
import '../services/inspect_service.dart';
import '../services/pdf_tools_service.dart';
import '../utils/format.dart';
import '../widgets/file_tile.dart';
import '../widgets/polo_message.dart';

/// Everything about one file or folder: details, what is inside, checksums.
class FileInspectorScreen extends StatefulWidget {
  const FileInspectorScreen({super.key, required this.item});

  final FileItem item;

  @override
  State<FileInspectorScreen> createState() => _FileInspectorScreenState();
}

class _FileInspectorScreenState extends State<FileInspectorScreen> {
  FileStat? _stat;
  (int, int)? _imageSize;
  int? _pages;
  TextStats? _text;
  FolderStats? _folder;
  Future<Checksums>? _checksums;
  bool _loading = true;

  FileItem get item => widget.item;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stat = await FileStat.stat(item.path);
    if (mounted) setState(() => _stat = stat);

    try {
      if (item.isDirectory) {
        _folder = await InspectService.folderStats(item.path);
      } else if (item.kind == FileKind.image) {
        _imageSize = await InspectService.imageSize(item.path);
      } else if (item.kind == FileKind.pdf) {
        _pages = await PdfToolsService(FileService()).pageCount(item.path);
      } else if (item.kind == FileKind.document || item.kind == FileKind.other) {
        _text = await InspectService.textStats(item.path);
      }
    } catch (_) {
      // Whatever could not be read is simply left out.
    }
    if (mounted) setState(() => _loading = false);
  }

  String _date(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${item.dateLabelFor(d)}, ${two(d.hour)}:${two(d.minute)}';
  }

  String _typeLabel() {
    if (item.isDirectory) return 'Folder';
    final ext = item.extension.toUpperCase();
    final kind = switch (item.kind) {
      FileKind.image => 'Picture',
      FileKind.video => 'Video',
      FileKind.audio => 'Audio',
      FileKind.pdf => 'PDF document',
      FileKind.document => 'Document',
      FileKind.archive => 'Archive',
      FileKind.apk => 'Android app',
      _ => 'File',
    };
    return ext.isEmpty ? kind : '$kind ($ext)';
  }

  String _bytes(int n) => '${formatBytes(n)} ($n bytes)';

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) showPoloMessage(context, '$label copied');
  }

  Widget _card(String title, List<Widget> children) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: scheme.primary)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool mono = false, String? copyLabel}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(label, style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65))),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: mono ? const TextStyle(fontFamily: 'monospace', fontSize: 12.5) : null,
            ),
          ),
          if (copyLabel != null)
            InkWell(
              onTap: () => _copy(copyLabel, value),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.copy_outlined, size: 18),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _contentRows() {
    final out = <Widget>[];
    final f = _folder;
    if (f != null) {
      out.add(_row('Files', '${f.files}'));
      out.add(_row('Folders', '${f.folders}'));
      out.add(_row('Total size', _bytes(f.bytes)));
    }
    final size = _imageSize;
    if (size != null) {
      out.add(_row('Dimensions', '${size.$1} × ${size.$2} pixels'));
      out.add(_row('Megapixels', (size.$1 * size.$2 / 1000000).toStringAsFixed(1)));
    }
    if (_pages != null) out.add(_row('Pages', '$_pages'));
    final t = _text;
    if (t != null) {
      out.add(_row('Lines', '${t.lines}'));
      out.add(_row('Words', '${t.words}'));
      out.add(_row('Characters', '${t.characters}'));
      out.add(_row('Encoding', t.utf8 ? 'UTF-8' : 'Not UTF-8 (read as Latin-1)'));
      out.add(_row('Line endings', t.windowsLineEndings ? 'Windows (CRLF)' : 'Unix (LF)'));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stat = _stat;
    final (icon, color) = fileIconFor(item.kind, scheme);
    final content = _contentRows();

    return Scaffold(
      appBar: AppBar(title: const Text('Inspect')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(item.name, style: Theme.of(context).textTheme.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _card('General', [
            _row('Type', _typeLabel()),
            if (!item.isDirectory) _row('Size', _bytes(item.size)),
            _row('Location', item.parentPath, mono: true, copyLabel: 'Location'),
            _row('Modified', _date(item.modified)),
            if (stat != null && stat.type != FileSystemEntityType.notFound) ...[
              _row('Last opened', _date(stat.accessed)),
              _row('Changed', _date(stat.changed)),
            ],
          ]),
          if (_loading && content.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (content.isNotEmpty)
            _card(item.isDirectory ? 'Inside' : 'Content', content),
          if (!item.isDirectory)
            _card('Checksums', [
              if (_checksums == null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FilledButton.tonalIcon(
                      onPressed: () => setState(() => _checksums = ChecksumService.compute(item.path)),
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('Calculate'),
                    ),
                  ),
                )
              else
                FutureBuilder<Checksums>(
                  future: _checksums,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: LinearProgressIndicator(),
                      );
                    }
                    if (snap.hasError) {
                      return const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text("Couldn't read this file"),
                      );
                    }
                    final c = snap.data!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _row('SHA-256', c.sha256, mono: true, copyLabel: 'SHA-256'),
                        _row('SHA-1', c.sha1, mono: true, copyLabel: 'SHA-1'),
                        _row('MD5', c.md5, mono: true, copyLabel: 'MD5'),
                      ],
                    );
                  },
                ),
            ]),
        ],
      ),
    );
  }
}