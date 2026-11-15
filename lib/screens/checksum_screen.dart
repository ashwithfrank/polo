import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/file_item.dart';
import '../services/checksum_service.dart';
import '../widgets/polo_message.dart';

class ChecksumScreen extends StatefulWidget {
  const ChecksumScreen({super.key, required this.file});

  final FileItem file;

  @override
  State<ChecksumScreen> createState() => _ChecksumScreenState();
}

class _ChecksumScreenState extends State<ChecksumScreen> {
  late final Future<Checksums> _future = ChecksumService.compute(widget.file.path);
  final _compare = TextEditingController();

  @override
  void dispose() {
    _compare.dispose();
    super.dispose();
  }

  /// Which algorithm [expected] matches, or null.
  String? _match(Checksums c) {
    final e = _compare.text.toLowerCase().replaceAll(RegExp(r'[\s:]'), '');
    if (e.isEmpty) return null;
    if (e == c.md5) return 'MD5';
    if (e == c.sha1) return 'SHA-1';
    if (e == c.sha256) return 'SHA-256';
    return null;
  }

  Widget _row(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_outlined, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              showPoloMessage(context, '$label copied');
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Checksum')),
      body: FutureBuilder<Checksums>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Calculating…'),
                ],
              ),
            );
          }
          if (snap.hasError) {
            return const Center(child: Text("Couldn't read this file"));
          }
          final c = snap.data!;
          final text = _compare.text.trim();
          final match = _match(c);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(widget.file.name, style: Theme.of(context).textTheme.titleMedium),
              Text(
                widget.file.sizeLabel,
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 12),
              _row(context, 'SHA-256', c.sha256),
              _row(context, 'SHA-1', c.sha1),
              _row(context, 'MD5', c.md5),
              const SizedBox(height: 16),
              TextField(
                controller: _compare,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Compare with a checksum',
                  hintText: 'Paste the checksum from the download page',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (text.isNotEmpty)
                Row(
                  children: [
                    Icon(
                      match != null ? Icons.check_circle : Icons.cancel_outlined,
                      color: match != null ? Colors.green : scheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        match != null
                            ? 'Match ($match). The file is intact.'
                            : "Doesn't match. Keep typing, or the file may be damaged or different.",
                        style: TextStyle(color: match != null ? Colors.green : scheme.error),
                      ),
                    ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}