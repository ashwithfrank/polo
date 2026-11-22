import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';

import '../models/file_item.dart';

/// Words, lines and characters in a text file.
class TextStatsScreen extends StatefulWidget {
  const TextStatsScreen({super.key, required this.item});

  final FileItem item;

  @override
  State<TextStatsScreen> createState() => _TextStatsScreenState();
}

class _Stats {
  const _Stats(this.words, this.lines, this.chars, this.charsNoSpaces, this.paragraphs);
  final int words;
  final int lines;
  final int chars;
  final int charsNoSpaces;
  final int paragraphs;
}

class _TextStatsScreenState extends State<TextStatsScreen> {
  _Stats? _stats;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final path = widget.item.path;
    try {
      if (widget.item.size > 20 * 1024 * 1024) {
        throw const FormatException('This file is too big to count (over 20 MB)');
      }
      final stats = await Isolate.run(() {
        final text = File(path).readAsStringSync();
        final words = RegExp(r'\S+').allMatches(text).length;
        final lines = text.isEmpty ? 0 : text.split('\n').length;
        final noSpaces = text.replaceAll(RegExp(r'\s'), '').length;
        final paragraphs =
            text.split(RegExp(r'\n\s*\n')).where((p) => p.trim().isNotEmpty).length;
        return _Stats(words, lines, text.length, noSpaces, paragraphs);
      });
      if (mounted) setState(() => _stats = stats);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't read this file as text");
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = _stats;
    String n(int v) => v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    final minutes = s == null ? 0 : (s.words / 200).ceil();

    return Scaffold(
      appBar: AppBar(title: const Text('Word count')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.description_outlined, color: scheme.primary),
            title: Text(widget.item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(widget.item.sizeLabel),
          ),
          const SizedBox(height: 8),
          if (_error != null)
            Text(_error!, style: TextStyle(color: scheme.error))
          else if (s == null)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else ...[
            for (final (label, value) in [
              ('Words', n(s.words)),
              ('Characters', n(s.chars)),
              ('Characters without spaces', n(s.charsNoSpaces)),
              ('Lines', n(s.lines)),
              ('Paragraphs', n(s.paragraphs)),
              ('Reading time', s.words == 0 ? '0 min' : '$minutes min'),
            ])
              ListTile(
                title: Text(label),
                trailing: Text(value, style: Theme.of(context).textTheme.titleMedium),
              ),
          ],
        ],
      ),
    );
  }
}
