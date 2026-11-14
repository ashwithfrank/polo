import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../models/storage_category.dart';
import '../widgets/delete_file.dart';
import '../services/storage_controller.dart';
import '../services/storage_info.dart';
import '../services/storage_scanner.dart';
import '../utils/format.dart';
import '../widgets/file_tile.dart';
import '../widgets/message_view.dart';
import '../widgets/open_file.dart';

class StorageScreen extends StatelessWidget {
  const StorageScreen({
    super.key,
    required this.controller,
    required this.onOpenCategory,
  });

  final StorageController controller;
  final void Function(StorageCategory category) onOpenCategory;

  Future<void> _confirmDelete(BuildContext context, FileItem item) async {
    final moved = await deleteFileWithConfirm(context, item);
    if (moved) await controller.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.needsAccess) {
          return MessageView(
            icon: Icons.folder_special_outlined,
            title: 'Allow access to your files',
            body: 'Polo needs permission to see your files so it can show what\'s using your storage.',
            actionLabel: 'Grant access',
            onAction: controller.requestAccess,
          );
        }

        final scheme = Theme.of(context).colorScheme;
        final info = controller.info;
        final scan = controller.scan;
        final titleStyle = Theme.of(context).textTheme.titleSmall;

        return RefreshIndicator(
          onRefresh: controller.load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              if (info != null) ...[
                Text(
                  '${formatBytes(info.used)} used',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatBytes(info.free)} free of ${formatBytes(info.total)}',
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
                ),
              ] else if (scan != null)
                Text(
                  '${formatBytes(scan.totalBytes)} in ${scan.totalFiles} files',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              const SizedBox(height: 14),
              _UsageBar(info: info, scan: scan),
              const SizedBox(height: 16),
              if (scan == null && controller.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Looking through your files…'),
                    ],
                  ),
                )
              else if (scan == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text(controller.error ?? 'Pull down to scan your files.')),
                )
              else ...[
                  ..._legend(context, scan),
                  const SizedBox(height: 24),
                  Text('Largest files', style: titleStyle),
                  const SizedBox(height: 4),
                  if (scan.largest.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('No files over 20 MB. Nothing big to clean up.'),
                    )
                  else
                    for (final item in scan.largest)
                      FileTile(
                        item: item,
                        onTap: () => openFile(context, item),
                        trailing: IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmDelete(context, item),
                        ),
                      ),
                ],
            ],
          ),
        );
      },
    );
  }

  List<Widget> _legend(BuildContext context, ScanResult scan) {
    final scheme = Theme.of(context).colorScheme;
    final categories = StorageCategory.values
        .where((c) => (scan.counts[c] ?? 0) > 0)
        .toList()
      ..sort((a, b) => scan.bytes[b]!.compareTo(scan.bytes[a]!));

    final info = controller.info;
    final system = info == null ? 0 : info.used - scan.totalBytes;

    Widget row(Color color, String title, String subtitle, int bytes,
        {VoidCallback? onTap}) {
      return ListTile(
        onTap: onTap,
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        title: Text(title),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        trailing: Text(formatBytes(bytes), style: const TextStyle(fontWeight: FontWeight.w600)),
      );
    }

    return [
      for (final c in categories)
        row(
          c.color,
          c.label,
          '${scan.counts[c]} ${scan.counts[c] == 1 ? 'file' : 'files'}',
          scan.bytes[c]!,
          onTap: () => onOpenCategory(c),
        ),
      if (system > 0)
        row(
          scheme.onSurface.withValues(alpha: 0.35),
          'System and app data',
          'Not visible to Polo',
          system,
        ),
    ];
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.info, required this.scan});

  final StorageInfo? info;
  final ScanResult? scan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final segments = <({int flex, Color color})>[];

    final i = info;
    final s = scan;
    final total = i?.total ?? s?.totalBytes ?? 0;
    int flexFor(int bytes) =>
        total == 0 ? 1 : ((bytes * 1000) ~/ total).clamp(1, 1000).toInt();

    if (s != null) {
      for (final c in StorageCategory.values) {
        final bytes = s.bytes[c] ?? 0;
        if (bytes > 0) segments.add((flex: flexFor(bytes), color: c.color));
      }
      if (i != null) {
        final system = i.used - s.totalBytes;
        if (system > 0) {
          segments.add((flex: flexFor(system), color: scheme.onSurface.withValues(alpha: 0.35)));
        }
      }
    } else if (i != null) {
      segments.add((flex: flexFor(i.used), color: scheme.primary));
    }

    if (i != null) {
      segments.add((flex: flexFor(i.free), color: scheme.surfaceContainerHighest));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 14,
        child: segments.isEmpty
            ? ColoredBox(color: scheme.surfaceContainerHighest)
            : Row(
          children: [
            for (final s in segments)
              Expanded(flex: s.flex, child: ColoredBox(color: s.color)),
          ],
        ),
      ),
    );
  }
}