import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/convert_service.dart';
import '../services/file_service.dart';

enum _Status { waiting, working, done, failed, skipped }

class _Job {
  _Job(this.item);

  final FileItem item;
  _Status status = _Status.waiting;
  String? detail;
}

class ConvertImagesScreen extends StatefulWidget {
  const ConvertImagesScreen({super.key, required this.files});

  final List<FileItem> files;

  @override
  State<ConvertImagesScreen> createState() => _ConvertImagesScreenState();
}

class _ConvertImagesScreenState extends State<ConvertImagesScreen> {
  final _service = ConvertService(FileService());

  late final List<_Job> _jobs = widget.files.map(_Job.new).toList();
  ImageTarget _target = ImageTarget.jpg;
  double _quality = 90;
  bool _running = false;
  bool _finished = false;

  int get _doneCount => _jobs.where((j) => j.status == _Status.done).length;

  Future<void> _run() async {
    setState(() => _running = true);

    for (final job in _jobs) {
      setState(() => job.status = _Status.working);

      if (ConvertService.isAlready(job.item, _target)) {
        job.status = _Status.skipped;
        job.detail = 'Already a ${_target.label}';
        setState(() {});
        continue;
      }

      try {
        final out = await _service.convertImage(
          job.item,
          _target,
          quality: _quality.round(),
        );
        job.status = _Status.done;
        job.detail = 'Saved as ${out.split('/').last}';
      } catch (e) {
        job.status = _Status.failed;
        job.detail = e is FormatException ? e.message : "Couldn't convert this file";
      }
      setState(() {});
    }

    setState(() {
      _running = false;
      _finished = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = _jobs.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Convert images')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          Text('Convert to', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<ImageTarget>(
            showSelectedIcon: false,
            segments: [
              for (final t in ImageTarget.values)
                ButtonSegment(value: t, label: Text(t.label)),
            ],
            selected: {_target},
            onSelectionChanged: _running
                ? null
                : (s) => setState(() {
                      _target = s.first;
                      _finished = false;
                      for (final j in _jobs) {
                        j.status = _Status.waiting;
                        j.detail = null;
                      }
                    }),
          ),
          if (_target == ImageTarget.jpg) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Quality', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                Text('${_quality.round()}'),
              ],
            ),
            Slider(
              value: _quality,
              min: 40,
              max: 100,
              divisions: 12,
              onChanged: _running ? null : (v) => setState(() => _quality = v),
            ),
            Text(
              'Lower quality makes smaller files.',
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 12),
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
                  ? 'Converting…'
                  : _finished
                      ? 'Done ($_doneCount converted)'
                      : 'Convert $count ${count == 1 ? 'image' : 'images'}',
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