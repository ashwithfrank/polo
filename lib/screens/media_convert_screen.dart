import 'dart:io';

import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/file_service.dart';
import '../services/media_service.dart';
import '../services/output_location.dart';
import '../widgets/pdf_result.dart';

enum MediaJob {
  compressVideo('Compress video', Icons.compress),
  videoToAudio('Video to audio', Icons.audiotrack_outlined),
  toM4a('Convert audio', Icons.music_note_outlined);

  const MediaJob(this.title, this.icon);
  final String title;
  final IconData icon;
}

/// Compress a video, pull the sound out of it, or convert an audio file.
class MediaConvertScreen extends StatefulWidget {
  const MediaConvertScreen({super.key, required this.item, required this.job});

  final FileItem item;
  final MediaJob job;

  @override
  State<MediaConvertScreen> createState() => _MediaConvertScreenState();
}

class _MediaConvertScreenState extends State<MediaConvertScreen> {
  int _height = 720;
  int _kbps = 2000;
  bool _busy = false;
  int _percent = 0;
  String? _error;
  String? _savedPath;
  String? _summary;

  static const _heights = [1080, 720, 480, 360];
  static const _qualities = [
    (4000, 'High'),
    (2000, 'Medium'),
    (1000, 'Small'),
    (500, 'Tiny'),
  ];

  bool get _audio => widget.job != MediaJob.compressVideo;

  @override
  void dispose() {
    if (_busy) MediaService.cancel();
    super.dispose();
  }

  String _size(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).round()} KB';
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _percent = 0;
      _error = null;
    });
    final item = widget.item;
    final dot = item.name.lastIndexOf('.');
    final base = dot > 0 ? item.name.substring(0, dot) : item.name;
    String? out;
    try {
      final dir = await OutputLocation.resolve(item.parentPath, OutputKind.media);
      final name = _audio ? '$base.m4a' : '$base (compressed).mp4';
      out = await FileService().uniquePath(dir, name);
      await MediaService.convert(
        input: item.path,
        output: out,
        audioOnly: _audio,
        height: _audio ? null : _height,
        videoKbps: _audio ? null : _kbps,
        onProgress: (p) {
          if (mounted) setState(() => _percent = p);
        },
      );
      final newSize = await File(out).length();
      OutputLocation.announce(out);
      if (!mounted) return;
      setState(() {
        _savedPath = out;
        _summary = '${_size(item.size)}  →  ${_size(newSize)}';
      });
    } on MediaCancelled {
      // The person backed out.
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't convert this file");
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = Theme.of(context).textTheme.titleSmall;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 12);
    final saved = _savedPath;

    return Scaffold(
      appBar: AppBar(title: Text(widget.job.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (saved != null) ...[
            SavedBanner(text: 'Saved ${saved.split('/').last}\n$_summary'),
            const SizedBox(height: 16),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(widget.job.icon, color: scheme.primary, size: 22),
            ),
            title: Text(widget.item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(_size(widget.item.size)),
          ),
          const SizedBox(height: 8),
          if (!_audio) ...[
            Text('Size on screen', style: title),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final h in _heights)
                  ChoiceChip(
                    label: Text('${h}p'),
                    selected: _height == h,
                    onSelected: _busy || saved != null ? null : (_) => setState(() => _height = h),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text('A video smaller than this keeps its own size.', style: muted),
            const SizedBox(height: 16),
            Text('Quality', style: title),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final q in _qualities)
                  ChoiceChip(
                    label: Text(q.$2),
                    selected: _kbps == q.$1,
                    onSelected: _busy || saved != null ? null : (_) => setState(() => _kbps = q.$1),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Lower quality makes a smaller file.', style: muted),
          ] else
            Text(
              widget.job == MediaJob.videoToAudio
                  ? 'Saves the sound of the video as an M4A file.'
                  : 'Converts the sound to M4A (AAC), which plays almost everywhere.',
              style: muted,
            ),
          if (_busy) ...[
            const SizedBox(height: 24),
            LinearProgressIndicator(value: _percent == 0 ? null : _percent / 100),
            const SizedBox(height: 8),
            Text('Working… $_percent%', style: muted),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: saved != null
              ? SavedActions(openPath: saved)
              : _busy
                  ? OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: MediaService.cancel,
                      child: const Text('Cancel'),
                    )
                  : FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: _run,
                      child: Text(_audio ? 'Save audio' : 'Compress'),
                    ),
        ),
      ),
    );
  }
}
