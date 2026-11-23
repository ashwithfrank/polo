import 'package:flutter/material.dart';

import '../services/file_service.dart';
import '../services/output_location.dart';
import '../services/settings_controller.dart';
import '../theme/theme_controller.dart';
import '../widgets/accent_picker.dart';
import 'about_screen.dart';
import 'customize_home_screen.dart';
import 'trash_screen.dart';
import '../widgets/haptics.dart';

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
              SwitchListTile(
                title: const Text('True black'),
                subtitle: const Text('A pure black dark theme. Saves battery on OLED screens'),
                value: themeController.oled,
                onChanged: themeController.setOled,
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text('Accent colour'),
              ),
              AccentPicker(controller: themeController),
              const _Section('Home'),
              ListTile(
                leading: const Icon(Icons.dashboard_customize_outlined),
                title: const Text('Customize Home'),
                subtitle: const Text('Hide or reorder blocks and pick quick access folders'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => CustomizeHomeScreen(settings: settings)),
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
              const _Section('Saving results'),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Where tools save what they make'),
              ),
              for (final o in const [
                (OutputMode.smart, 'Smart (recommended)',
                    'Edits stay next to the original. Scans, QR codes and other new things go to the Polo folder'),
                (OutputMode.nextToOriginal, 'Next to the original',
                    'Scans and QR codes still go to the Polo folder'),
                (OutputMode.poloFolder, 'Always the Polo folder',
                    'Polo/Images, Documents, Scans, QR codes, Archives'),
              ])
                ListTile(
                  leading: Icon(
                    settings.outputMode == o.$1
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: settings.outputMode == o.$1
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(o.$2),
                  subtitle: Text(o.$3),
                  onTap: () => settings.setOutputMode(o.$1),
                ),
              const _Section('Selecting files'),
              SwitchListTile(
                title: const Text('Slide to select'),
                subtitle: const Text('Hold a file, then slide up or down to select more'),
                value: settings.dragSelect,
                onChanged: settings.setDragSelect,
              ),
              ListTile(
                title: const Text('Hold time'),
                subtitle: Text('${settings.longPressMs} ms. Shorter selects faster'),
              ),
              Slider(
                min: 250,
                max: 1000,
                divisions: 15,
                label: '${settings.longPressMs} ms',
                value: settings.longPressMs.toDouble().clamp(250, 1000),
                onChanged: (v) => settings.setLongPressMs(v.round()),
              ),
              const _Section('Feel'),
              SwitchListTile(
                title: const Text('Vibration'),
                subtitle: const Text('A small buzz when you select or switch tabs'),
                value: settings.haptics,
                onChanged: settings.setHaptics,
              ),
              if (settings.haptics)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 1, label: Text('Light')),
                      ButtonSegment(value: 2, label: Text('Medium')),
                      ButtonSegment(value: 3, label: Text('Strong')),
                    ],
                    selected: {settings.hapticStrength},
                    onSelectionChanged: (v) {
                      settings.setHapticStrength(v.first);
                      Haptics.test();
                    },
                  ),
                ),
              SwitchListTile(
                title: const Text('Animations'),
                subtitle: const Text('Fades, slides and press effects'),
                value: settings.animations,
                onChanged: settings.setAnimations,
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
