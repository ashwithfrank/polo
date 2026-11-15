import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/file_item.dart';
import '../services/convert_service.dart';
import '../services/file_service.dart';
import '../utils/format.dart';

enum _Status { waiting, working, done, failed, skipped }

class _Job {
  _Job(this.item);

  final FileItem item;
  _Status status = _Status.waiting;
  String? detail;
}

class ConvertImagesScreen extends StatefulWidget {
  const ConvertImagesScreen({
    super.key,
    required this.files,
    this.keepFormat = false,
  });

  final List<FileItem> files;

  /// True for "Resize and compress": each image keeps its own format.
  final bool keepFormat;

  @override
  State<ConvertImagesScreen> createState() => _ConvertImagesScreenState();
}

class _ConvertImagesScreenState extends State<ConvertImagesScreen> {
  final _service = ConvertService(FileService());

  late final List<_Job> _jobs = widget.files.map(_Job.new).toList();
  ImageTarget _target = ImageTarget.jpg;
  double _quality = 85;
  int? _maxSide;
  bool _running = false;
  bool _finished = false;

  int get _doneCount => _jobs.where((j) => j.status == _Status.done).length;

  static const _sizes = <int?>[null, 2560, 1920, 1280, 800];

  bool get _showQuality => widget.keepFormat || _target.usesQuality;

  /// Forget earlier results when an option changes.
  void _optionChanged(VoidCallback change) {
    setState(() {
      change();
      _finished = false;
      for (final j in _jobs) {
        j.status = _Status.waiting;
        j.detail = null;
      }
    });
  }

  Future<void> _run() async {
    setState(() => _running = true);

    for (final job in _jobs) {
      setState(() => job.status = _Status.working);

      if (!widget.keepFormat && _maxSide == null && ConvertService.isAlready(job.item, _target)) {
        job.status = _Status.skipped;
        job.detail = 'Already a ${_target.label}';
        setState(() {});
        continue;
      }

      try {
        final out = await _service.convertImage(
          job.item,
          target: widget.keepFormat ? null : _target,
          quality: _quality.round(),
          maxSide: _maxSide,
        );
        job.status = _Status.done;
        job.detail = 'Saved as ${out.name} · ${formatBytes(job.item.size)} to ${formatBytes(out.bytes)}';
      } catch (e) {
        job.status = _Status.failed;
        if (e is FormatException) {
          job.detail = e.message;
        } else if (e is MissingPluginException) {
          job.detail = 'WebP needs a full restart of the app (stop it, then run again)';
        } else {
          final text = e.toString().replaceAll('\n', ' ');
          job.detail = "Couldn't convert this file: ${text.length > 120 ? text.substring(0, 120) : text}";
        }
      }
      setState(() {});
    }

    setState(() {
      _running = false;
      _finished = true;
    });
  }

  Widget _hint(ColorScheme scheme, String text) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      text,
      style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 12),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = _jobs.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.keepFormat ? 'Resize and compress' : 'Convert images'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          if (!widget.keepFormat) ...[
            Text('Convert to', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final t in ImageTarget.values)
                  ChoiceChip(
                    label: Text(t.label),
                    selected: _target == t,
                    onSelected: _running ? null : (_) => _optionChanged(() => _target = t),
                  ),
              ],
            ),
            if (_target == ImageTarget.gif)
              _hint(scheme, 'GIF keeps one frame, so animations become a still picture.'),
            if (_target == ImageTarget.ico)
              _hint(scheme, 'Icons are limited to 256 pixels, so bigger images are shrunk.'),
          ] else
            _hint(scheme, 'Each image keeps its format. The originals are never changed.'),
          const SizedBox(height: 20),
          Text('Longest side', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final size in _sizes)
                ChoiceChip(
                  label: Text(size == null ? 'Original' : '$size px'),
                  selected: _maxSide == size,
                  onSelected: _running ? null : (_) => _optionChanged(() => _maxSide = size),
                ),
            ],
          ),
          _hint(scheme, 'Smaller images are never enlarged.'),
          if (_showQuality) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Text('Quality', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                Text('${_quality.round()}'),
              ],
            ),
            Slider(
              value: _quality,
              min: 30,
              max: 100,
              divisions: 14,
              onChanged: _running ? null : (v) => _optionChanged(() => _quality = v),
            ),
            _hint(
              scheme,
              widget.keepFormat
                  ? 'Lower quality makes smaller files. Applies to JPG and WebP images.'
                  : 'Lower quality makes smaller files.',
            ),
          ],
          const SizedBox(height: 20),
          Text(
            count == 1 ? '1 image' : '$count images',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          for (final job in _jobs) _JobRow(job: job),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _running
                ? null
                : _finished
                ? () => Navigator.pop(context)
                : _run,
            child: Text(
              _running
                  ? 'Working…'
                  : _finished
                  ? 'Done ($_doneCount saved)'
                  : '${widget.keepFormat ? 'Shrink' : 'Convert'} $count ${count == 1 ? 'image' : 'images'}',
            ),
          ),
        ),
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({required this.job});

  final _Job job;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final Widget trailing = switch (job.status) {
      _Status.waiting => const SizedBox.shrink(),
      _Status.working => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      _Status.done => Icon(Icons.check_circle, color: scheme.primary),
      _Status.failed => Icon(Icons.error_outline, color: scheme.error),
      _Status.skipped => Icon(Icons.remove_circle_outline, color: scheme.onSurface.withValues(alpha: 0.5)),
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.pink.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.image_outlined, color: Colors.pink, size: 22),
      ),
      title: Text(job.item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        job.detail ?? job.item.sizeLabel,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: job.status == _Status.failed
              ? scheme.error
              : scheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
      trailing: trailing,
    );
  }
}