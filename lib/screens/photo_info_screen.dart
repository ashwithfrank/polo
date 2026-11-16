import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/file_item.dart';
import '../services/image_meta.dart';
import '../utils/format.dart';
import '../widgets/polo_message.dart';
import 'strip_metadata_screen.dart';

/// Shows what is hidden inside a picture: size, camera, date, location.
class PhotoInfoScreen extends StatefulWidget {
  const PhotoInfoScreen({super.key, required this.item});

  final FileItem item;

  @override
  State<PhotoInfoScreen> createState() => _PhotoInfoScreenState();
}

class _PhotoInfoScreenState extends State<PhotoInfoScreen> {
  late final Future<PhotoInfo> _info = readPhotoInfo(widget.item.path);

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showPoloMessage(context, 'Copied');
  }

  Widget _card(BuildContext context, String title, List<InfoRow> rows) {
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
            Text(
              title,
              style: TextStyle(fontWeight: FontWeight.w600, color: scheme.primary),
            ),
            const SizedBox(height: 8),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        r.label,
                        style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
                      ),
                    ),
                    Expanded(child: SelectableText(r.value)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = widget.item;

    return Scaffold(
      appBar: AppBar(title: const Text('Photo info')),
      body: FutureBuilder<PhotoInfo>(
        future: _info,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const Center(child: Text("Couldn't read this picture"));
          }
          final info = snapshot.data!;
          final canClean = strippableExtensions.contains(item.extension);

          final basics = <InfoRow>[
            InfoRow('Name', item.name),
            InfoRow('Format', info.format),
            InfoRow('Size', formatBytes(info.bytes)),
            if (info.width != null && info.height != null) ...[
              InfoRow('Dimensions', '${info.width} × ${info.height} px'),
              InfoRow(
                'Megapixels',
                '${(info.width! * info.height! / 1000000).toStringAsFixed(1)} MP',
              ),
            ],
            InfoRow('Folder', item.parentPath),
          ];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 200,
                  child: Image.file(
                    File(item.path),
                    fit: BoxFit.cover,
                    cacheWidth: 900,
                    errorBuilder: (_, _, _) => ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: const Center(child: Icon(Icons.broken_image_outlined)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (info.hasLocation)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.location_on_outlined, color: scheme.onErrorContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This photo shows where it was taken. Remove the metadata before sharing it publicly.',
                          style: TextStyle(color: scheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              _card(context, 'File', basics),
              for (final s in info.sections) _card(context, s.title, s.rows),
              if (!info.hasExif)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    info.format == 'JPEG'
                        ? 'No camera, date or location data found in this photo.'
                        : 'Camera details are shown for JPEG photos.',
                    style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
                  ),
                ),
              if (info.hasLocation)
                OutlinedButton.icon(
                  onPressed: () => _copy(
                    '${info.latitude!.toStringAsFixed(6)}, ${info.longitude!.toStringAsFixed(6)}',
                  ),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy coordinates'),
                ),
              if (canClean) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StripMetadataScreen(files: [item]),
                    ),
                  ),
                  icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                  label: const Text('Remove metadata'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}