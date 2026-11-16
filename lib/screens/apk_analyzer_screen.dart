import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/file_item.dart';
import '../services/apk_service.dart';
import '../utils/format.dart';
import '../widgets/polo_message.dart';

/// Shows what is inside an APK file without installing it.
class ApkAnalyzerScreen extends StatefulWidget {
  const ApkAnalyzerScreen({super.key, required this.item});

  final FileItem item;

  @override
  State<ApkAnalyzerScreen> createState() => _ApkAnalyzerScreenState();
}

class _ApkAnalyzerScreenState extends State<ApkAnalyzerScreen> {
  late final Future<ApkInfo> _info = ApkService.analyze(widget.item.path);

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showPoloMessage(context, 'Copied');
  }

  Widget _card(BuildContext context, String title, List<Widget> children) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
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
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  /// A closed list of names, such as all the activities.
  Widget _names(BuildContext context, String title, List<String> names) {
    final scheme = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text('$title (${names.length})'),
        enabled: names.isNotEmpty,
        children: [
          for (final n in names)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SelectableText(
                  n,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('APK analyzer')),
      body: FutureBuilder<ApkInfo>(
        future: _info,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final e = snapshot.error;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  e is FormatException ? e.message : "Couldn't read this APK",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.error),
                ),
              ),
            );
          }

          final info = snapshot.data!;
          final dangerous = info.permissions.where((p) => p.dangerous).toList();
          final other = info.permissions.where((p) => !p.dangerous).toList();
          final cert = info.certificate;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: info.icon == null
                        ? Container(
                      width: 64,
                      height: 64,
                      color: scheme.surfaceContainerHighest,
                      child: const Icon(Icons.android, size: 32),
                    )
                        : Image.memory(info.icon!, width: 64, height: 64),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          info.appName.isEmpty ? widget.item.name : info.appName,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        InkWell(
                          onTap: () => _copy(info.packageName),
                          child: Text(
                            info.packageName,
                            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _card(context, 'Version', [
                _row(context, 'Version name', info.versionName.isEmpty ? '-' : info.versionName),
                _row(context, 'Version code', '${info.versionCode}'),
                _row(context, 'File size', formatBytes(info.size)),
              ]),
              _card(context, 'Android versions', [
                _row(
                  context,
                  'Minimum',
                  info.minSdk == null ? 'Unknown' : androidVersionLabel(info.minSdk!),
                ),
                _row(
                  context,
                  'Target',
                  info.targetSdk == null ? 'Unknown' : androidVersionLabel(info.targetSdk!),
                ),
              ]),
              _card(context, 'Permissions (${info.permissions.length})', [
                if (info.permissions.isEmpty) const Text('This app asks for no permissions.'),
                if (dangerous.isNotEmpty) ...[
                  Text(
                    'Needs your approval',
                    style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final p in dangerous)
                        Chip(
                          label: Text(p.shortName, style: const TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: scheme.errorContainer,
                          side: BorderSide.none,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (other.isNotEmpty) ...[
                  Text('Other', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final p in other)
                        Chip(
                          label: Text(p.shortName, style: const TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                          side: BorderSide.none,
                        ),
                    ],
                  ),
                ],
              ]),
              _card(context, 'Parts of the app', [
                _names(context, 'Activities', info.activities),
                _names(context, 'Services', info.services),
                _names(context, 'Broadcast receivers', info.receivers),
                _names(context, 'Content providers', info.providers),
              ]),
              if (cert != null)
                _card(context, 'Signing certificate', [
                  _row(context, 'Owner', cert.subject),
                  _row(context, 'Issuer', cert.issuer),
                  _row(context, 'Valid from', cert.validFrom),
                  _row(context, 'Valid until', cert.validTo),
                  _row(context, 'SHA-256', cert.sha256),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _copy(cert.sha256),
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy fingerprint'),
                    ),
                  ),
                ])
              else
                _card(context, 'Signing certificate', [
                  const Text('This APK is not signed, or the signature could not be read.'),
                ]),
            ],
          );
        },
      ),
    );
  }
}