import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  static const _repoUrl = 'https://github.com/ashwithfrank/polo';

  late final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: FutureBuilder<PackageInfo>(
        future: _info,
        builder: (context, snapshot) {
          final info = snapshot.data;
          final version = info == null
              ? ''
              : 'Version ${info.version} (${info.buildNumber})';

          return ListView(
            children: [
              const SizedBox(height: 32),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset(
                    'assets/icon/icon.png',
                    width: 88,
                    height: 88,
                    errorBuilder: (_, _, _) => Container(
                      width: 88,
                      height: 88,
                      color: scheme.primaryContainer,
                      child: Icon(Icons.folder_rounded, size: 44, color: scheme.primary),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Polo',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  version,
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
                child: Text(
                  'A fast, clean file manager for Android with built-in tools.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.8)),
                ),
              ),
              const Divider(height: 1),
              const ListTile(
                leading: Icon(Icons.code),
                title: Text('Made by'),
                subtitle: Text('AlphaOmega Studio'),
              ),
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Package'),
                subtitle: Text(info?.packageName ?? 'com.aos.polo'),
              ),
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Source code'),
                subtitle: const Text('github.com/ashwithfrank/polo'),
                onTap: () async {
                  await Clipboard.setData(const ClipboardData(text: _repoUrl));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(const SnackBar(content: Text('Link copied')));
                },
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Open source licenses'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Polo',
                  applicationVersion: info?.version,
                  applicationLegalese: '© 2026 AlphaOmega Studio',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}