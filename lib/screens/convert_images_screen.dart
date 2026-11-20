import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/file_item.dart';
import '../services/convert_service.dart';
import '../services/file_service.dart';
import '../services/inspect_service.dart';
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
    this.share = false,
  });

  final List<FileItem> files;

  /// True for "Resize and compress": each image keeps its own format.
  final bool keepFormat;

  /// True for "Compress for sharing": adds WhatsApp / Email / Website presets.
  final bool share;

  @override
  State<ConvertImagesScreen> createState() => _ConvertImagesScreenState();
}

class _ConvertImagesScreenState extends State<ConvertImagesScreen> {
  final _service = ConvertService(FileService());

  late final List<_Job> _jobs = widget.files.map(_Job.new).toList();
  ImageTarget _target = ImageTarget.jpg;
  double _quality = 85;
  int? _maxSide;
  String? _preset;
  bool _running = false;
  bool _finished = false;

  // The live before/after preview of the first picture.
  Uint8List? _previewBytes;
  (int, int)? _previewSize;
  (int, int)? _originalSize;
  bool _previewing = false;
  bool _previewSkipped = false;
  Timer? _previewTimer;
  int _previewToken = 0;

  @override
  void initState() {
    super.initState();
    InspectService.imageSize(_jobs.first.item.path).then((size) {
      if (mounted) setState(() => _originalSize = size);
    });
    _schedulePreview();
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    super.dispose();
  }

  /// Rebuilds the preview shortly after the last change, so dragging the
  /// slider doesn't start a job at every step.
  void _schedulePreview() {
    _previewTimer?.cancel();
    final token = ++_previewToken;
    final item = _jobs.first.item;

    if (!widget.keepFormat && _maxSide == null && ConvertService.isAlready(item, _target)) {
      setState(() {
        _previewSkipped = true;
        _previewing = false;
        _previewBytes = null;
      });
      return;
    }
    setState(() {
      _previewSkipped = false;
      _previewing = true;
    });

    _previewTimer = Timer(const Duration(milliseconds: 450), () async {
      Uint8List? bytes;
      (int, int)? size;
      try {
        bytes = await _service.encode(
          item,
          widget.keepFormat
              ? (ImageTargetX.fromExtension(item.extension) ?? ImageTarget.png)
              : _target,
          _quality.round(),
          _maxSide,
        );
        size = await InspectService.imageSizeOfBytes(bytes);
      } catch (_) {
        bytes = null;
      }
      // A newer change already started another preview.
      if (!mounted || token != _previewToken) return;
      setState(() {
        _previewBytes = bytes;
        _previewSize = size;
        _previewing = false;
      });
    });
  }

  Widget _panel(BuildContext context, String title, Widget picture, String detail, {Color? detailColor}) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.primary),
          ),
          const SizedBox(height: 6),
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(color: scheme.surfaceContainerHighest, child: picture),
            ),
          ),
          const SizedBox(height: 6),
          Text(detail, style: TextStyle(fontSize: 12, color: detailColor)),
        ],
      ),
    );
  }

  Widget _previewCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = _jobs.first.item;
    final before = item.size;
    final bytes = _previewBytes;

    String dims((int, int)? s) => s == null ? '' : '${s.$1} × ${s.$2}';

    String resultDetail;
    Color? color;
    if (_previewSkipped) {
      resultDetail = 'Already a ${_target.label}. Pick a size or another format.';
    } else if (bytes == null) {
      resultDetail = _previewing ? 'Working it out…' : 'No preview available';
    } else {
      final change = ((bytes.length - before) / before * 100).round();
      final label = change == 0
          ? 'same size'
          : change < 0
          ? '${-change}% smaller'
          : '$change% bigger';
      resultDetail = '${formatBytes(bytes.length)} · $label\n${dims(_previewSize)}';
      color = change <= 0 ? Colors.green : scheme.error;
    }

    final Widget result = bytes == null
        ? Center(
      child: _previewing
          ? const CircularProgressIndicator(strokeWidth: 3)
          : Icon(Icons.image_not_supported_outlined, color: scheme.onSurface.withValues(alpha: 0.5)),
    )
        : Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(
          bytes,
          fit: BoxFit.contain,
          cacheWidth: 700,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => Center(
            child: Text(
              'Preview not available\nfor ${_target.label}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
        if (_previewing)
          const Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _panel(
                context,
                'BEFORE',
                Image.file(
                  File(item.path),
                  fit: BoxFit.contain,
                  cacheWidth: 700,
                  errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined)),
                ),
                '${formatBytes(before)}\n${dims(_originalSize)}',
              ),
              const SizedBox(width: 12),
              _panel(context, 'AFTER', result, resultDetail, detailColor: color),
            ],
          ),
          if (_jobs.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Preview of ${item.name}. The other ${_jobs.length - 1} get the same settings.',
                style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.6)),
              ),
            ),
        ],
      ),
    );
  }

  int get _doneCount => _jobs.where((j) => j.status == _Status.done).length;

  static const _sizes = <int?>[null, 2560, 1920, 1600, 1280, 1024, 800];

  static const _presets = <({String label, int side, int quality, String hint})>[
    (label: 'WhatsApp', side: 1600, quality: 75, hint: 'Good for chats'),
    (label: 'Email', side: 1280, quality: 70, hint: 'Small attachments'),
    (label: 'Website', side: 1920, quality: 80, hint: 'Sharp on big screens'),
    (label: 'Smallest', side: 1024, quality: 50, hint: 'As small as it gets'),
  ];

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
    _schedulePreview();
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
        title: Text(
          widget.share
              ? 'Compress for sharing'
              : widget.keepFormat
              ? 'Resize and compress'
              : 'Convert images',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          _previewCard(context),
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
          if (widget.share) ...[
            const SizedBox(height: 20),
            Text('Made for', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final p in _presets)
                  ChoiceChip(
                    label: Text(p.label),
                    selected: _preset == p.label,
                    onSelected: _running
                        ? null
                        : (_) => _optionChanged(() {
                      _preset = p.label;
                      _maxSide = p.side;
                      _quality = p.quality.toDouble();
                    }),
                  ),
              ],
            ),
            _hint(
              scheme,
              _preset == null
                  ? 'Pick one, or set the size and quality yourself below.'
                  : '${_presets.firstWhere((p) => p.label == _preset).hint}. '
                  'Photos are shrunk on your phone. Nothing is uploaded.',
            ),
          ],
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
                  onSelected: _running
                      ? null
                      : (_) => _optionChanged(() {
                    _maxSide = size;
                    _preset = null;
                  }),
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
              onChanged: _running
                  ? null
                  : (v) => _optionChanged(() {
                _quality = v;
                _preset = null;
              }),
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