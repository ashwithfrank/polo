import 'dart:io';

import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/file_service.dart';
import '../services/image_meta.dart';
import '../utils/format.dart';
import '../services/output_location.dart';

enum _Status { waiting, working, done, failed, skipped }

class _Job {
  _Job(this.item);

  final FileItem item;
  _Status status = _Status.waiting;
  String? detail;
}

/// Saves a copy of each picture without its hidden data (location, camera,
/// dates...). The picture itself is copied exactly, so nothing is lost.
class StripMetadataScreen extends StatefulWidget {
  const StripMetadataScreen({super.key, required this.files});

  final List<FileItem> files;

  @override
  State<StripMetadataScreen> createState() => _StripMetadataScreenState();
}

class _StripMetadataScreenState extends State<StripMetadataScreen> {
  final _files = FileService();
  late final List<_Job> _jobs = widget.files.map(_Job.new).toList();
  bool _running = false;
  bool _finished = false;

  int get _doneCount => _jobs.where((j) => j.status == _Status.done).length;

  Future<void> _run() async {
    setState(() => _running = true);

    for (final job in _jobs) {
      setState(() => job.status = _Status.working);
      final item = job.item;
      try {
        if (!strippableExtensions.contains(item.extension)) {
          throw const FormatException('Only JPG, PNG and WebP can be cleaned');
        }
        final dot = item.name.lastIndexOf('.');
        final base = dot > 0 ? item.name.substring(0, dot) : item.name;
        final outPath = await _files.uniquePath(
          await OutputLocation.resolve(item.parentPath, OutputKind.images),
          '${base}_clean.${item.extension}',
        );
        final result = await stripMetadataFile(item.path, outPath);
        if (result.removed <= 0) {
          // Nothing was hidden in it, so a copy would be pointless.
          await File(outPath).delete();
          job.status = _Status.skipped;
          job.detail = 'No hidden data found';
        } else {
          job.status = _Status.done;
          job.detail = 'Saved as ${result.name} · removed ${formatBytes(result.removed)}';
        }
      } catch (e) {
        job.status = _Status.failed;
        job.detail = e is FormatException
            ? e.message
            : "Couldn't clean this file";
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
      appBar: AppBar(title: const Text('Remove metadata')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          Text(
            'Removes the location, camera, date and other hidden details. '
            'The picture itself is copied exactly, with no loss of quality, '
            'and your original is never changed.',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 20),
          Text(
            count == 1 ? '1 picture' : '$count pictures',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          for (final job in _jobs) _row(context, job),
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
                      : 'Clean $count ${count == 1 ? 'picture' : 'pictures'}',
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, _Job job) {
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
      _Status.skipped =>
        Icon(Icons.remove_circle_outline, color: scheme.onSurface.withValues(alpha: 0.5)),
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
