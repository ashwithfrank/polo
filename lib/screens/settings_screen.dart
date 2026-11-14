import 'package:flutter/material.dart';

import '../services/file_service.dart';
import '../services/settings_controller.dart';
import '../theme/theme_controller.dart';
import 'about_screen.dart';
import 'trash_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.themeController,
    required this.settings,
  });

  final ThemeController themeController;
  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: Listenable.merge([themeController, settings]),
        builder: (context, _) {
          return ListView(
            children: [
              const _Section('Appearance'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto_outlined),
                      label: Text('System'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('Light'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('Dark'),
                    ),
                  ],
                  selected: {themeController.mode},
                  onSelectionChanged: (s) => themeController.setMode(s.first),
                ),
              ),
              const _Section('Browsing'),
              SwitchListTile(
                title: const Text('Show hidden files'),
                subtitle: const Text('Files and folders that start with a dot'),
                value: settings.showHidden,
                onChanged: settings.setShowHidden,
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text('Sort files by'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<SortBy>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: SortBy.name, label: Text('Name')),
                    ButtonSegment(value: SortBy.date, label: Text('Date')),
                    ButtonSegment(value: SortBy.size, label: Text('Size')),
                  ],
                  selected: {settings.sortBy},
                  onSelectionChanged: (s) => settings.setSortBy(s.first),
                ),
              ),
              const _Section('Files'),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Trash'),
                subtitle: const Text('Restore deleted files'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TrashScreen()),
                ),
              ),
              const _Section('About'),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('About Polo'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutScreen()),
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}