import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/file_item.dart';
import '../../widgets/open_external.dart';

const _maxBytes = 300 * 1024;
const _linesPerChunk = 40;

class _Loaded {
  const _Loaded(this.chunks, this.truncated);
  final List<String> chunks;
  final bool truncated;
}

/// Reads up to [_maxBytes] of [path]. Returns null if it isn't plain text.
Future<_Loaded?> _load(String path) async {
  final file = File(path);
  final length = await file.length();
  final builder = BytesBuilder();
  await for (final chunk in file.openRead(0, length < _maxBytes ? length : _maxBytes)) {
    builder.add(chunk);
  }
  final bytes = builder.takeBytes();

  final probe = bytes.length < 4096 ? bytes : bytes.sublist(0, 4096);
  if (probe.contains(0)) return null; // binary

  final lines = const LineSplitter().convert(utf8.decode(bytes, allowMalformed: true));
  final chunks = <String>[];
  for (var i = 0; i < lines.length; i += _linesPerChunk) {
    final end = i + _linesPerChunk < lines.length ? i + _linesPerChunk : lines.length;
    chunks.add(lines.sublist(i, end).join('\n'));
  }
  return _Loaded(chunks, length > _maxBytes);
}

class TextPage extends StatefulWidget {
  const TextPage({super.key, required this.item});

  final FileItem item;

  @override
  State<TextPage> createState() => _TextPageState();
}

class _TextPageState extends State<TextPage> {
  late final Future<_Loaded?> _future = _load(widget.item.path);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FutureBuilder<_Loaded?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snap.data;
        if (snap.hasError || data == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined, size: 56, color: scheme.primary),
                  const SizedBox(height: 12),
                  const Text("Polo can't show this file as text", textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => openExternally(context, widget.item),
                    child: const Text('Open with another app'),
                  ),
                ],
              ),
            ),
          );
        }

        return Scrollbar(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: data.chunks.length + (data.truncated ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == data.chunks.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    'Showing the first ${_maxBytes ~/ 1024} KB. Open with another app to see the rest.',
                    style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
                  ),
                );
              }
              return SelectableText(
                data.chunks[i],
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4),
              );
            },
          ),
        );
      },
    );
  }
}