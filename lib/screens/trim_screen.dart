import 'dart:io';

import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/file_service.dart';
import '../services/media_service.dart';
import '../services/mp4_repair.dart';
import '../services/output_location.dart';
import '../widgets/pdf_result.dart';

/// Cut the start and end off a song, a voice note or a video.
class TrimScreen extends StatefulWidget {
  const TrimScreen({super.key, required this.item});

  final FileItem item;

  @override
  State<TrimScreen> createState() => _TrimScreenState();
}

class _TrimScreenState extends State<TrimScreen> {
  int _length = 0;
  bool _loaded = false;
  RangeValues _range = const RangeValues(0, 1);
  bool _busy = false;
  int _percent = 0;
  String? _error;
  String? _savedPath;

  bool get _video => widget.item.kind == FileKind.video;

  /// The file that gets trimmed. Usually the original; a repaired copy for
  /// videos that don't say how long they are.
  late String _source = widget.item.path;
  Directory? _tmp;
  bool _repairing = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    var ms = await MediaService.duration(widget.item.path);
    if (ms <= 0 && _video) {
      // Some videos (cut short or recorded in pieces) have no length stored.
      // The same repair the player uses gives them one.
      try {
        if (await Mp4Repair.needsRepair(widget.item.path)) {
          if (!mounted) return;
          setState(() => _repairing = true);
          final tmp = await Directory.systemTemp.createTemp('polo_trim');
          _tmp = tmp;
          final fixed = '${tmp.path}/video.mp4';
          final error = await Mp4Repair.makeSeekable(widget.item.path, fixed);
          if (error == null) {
            _source = fixed;
            ms = await MediaService.duration(fixed);
          }
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _repairing = false;
      _length = ms;
      _loaded = true;
      _range = RangeValues(0, ms.toDouble());
    });
  }

  @override
  void dispose() {
    if (_busy) MediaService.cancel();
    try {
      _tmp?.deleteSync(recursive: true);
    } catch (_) {}
    super.dispose();
  }

  String _time(num ms) {
    final total = (ms / 1000);
    final m = total ~/ 60;
    final s = total - m * 60;
    return '$m:${s.toStringAsFixed(1).padLeft(4, '0')}';
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
    try {
      final dir = await OutputLocation.resolve(item.parentPath, OutputKind.media);
      final out = await FileService().uniquePath(dir, '$base (trimmed).${_video ? 'mp4' : 'm4a'}');
      await MediaService.convert(
        input: _source,
        output: out,
        audioOnly: !_video,
        startMs: _range.start.round(),
        endMs: _range.end.round(),
        onProgress: (p) {
          if (mounted) setState(() => _percent = p);
        },
      );
      OutputLocation.announce(out);
      if (!mounted) return;
      setState(() => _savedPath = out);
    } on MediaCancelled {
      // Backed out.
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't trim this file");
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 12);
    final saved = _savedPath;
    final keep = (_range.end - _range.start).round();

    return Scaffold(
      appBar: AppBar(title: Text(_video ? 'Trim video' : 'Trim audio')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (saved != null) ...[
            SavedBanner(text: 'Saved ${saved.split('/').last}'),
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
              child: Icon(
                _video ? Icons.movie_outlined : Icons.audiotrack_outlined,
                color: scheme.primary,
                size: 22,
              ),
            ),
            title: Text(widget.item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(_loaded && _length > 0 ? 'Length ${_time(_length)}' : widget.item.sizeLabel),
          ),
          const SizedBox(height: 16),
          if (!_loaded)
            Column(
              children: [
                const Center(child: CircularProgressIndicator()),
                if (_repairing) ...[
                  const SizedBox(height: 12),
                  Text('Fixing the video so it can be trimmed…', style: muted),
                ],
              ],
            )
          else if (_length <= 0)
            Text("Polo can't read the length of this file.", style: TextStyle(color: scheme.error))
          else ...[
            RangeSlider(
              min: 0,
              max: _length.toDouble(),
              values: _range,
              labels: RangeLabels(_time(_range.start), _time(_range.end)),
              onChanged: _busy || saved != null
                  ? null
                  : (v) {
                      final max = _length.toDouble();
                      final start = ((v.start / 100).roundToDouble() * 100).clamp(0.0, max);
                      final end = ((v.end / 100).roundToDouble() * 100).clamp(start, max);
                      setState(() => _range = RangeValues(start, end));
                    },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Start ${_time(_range.start)}'),
                Text('End ${_time(_range.end)}'),
              ],
            ),
            const SizedBox(height: 8),
            Text('The new file will be ${_time(keep)} long.', style: muted),
            const SizedBox(height: 4),
            Text(
              _video
                  ? 'Saved as an MP4. Everything outside the two handles is removed.'
                  : 'Saved as an M4A. Everything outside the two handles is removed.',
              style: muted,
            ),
          ],
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
                      onPressed: !_loaded || _length <= 0 || keep < 500 ? null : _run,
                      child: const Text('Save trimmed copy'),
                    ),
        ),
      ),
    );
  }
}
