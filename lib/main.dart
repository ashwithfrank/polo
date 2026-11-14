import 'package:flutter/material.dart';

import 'screens/home_shell.dart';
import 'services/settings_controller.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeController = ThemeController();
  final settings = SettingsController();
  await Future.wait([themeController.load(), settings.load()]);
  runApp(PoloApp(themeController: themeController, settings: settings));
}

class PoloApp extends StatelessWidget {
  const PoloApp({
    super.key,
    required this.themeController,
    required this.settings,
  });

  final ThemeController themeController;
  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'Polo',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeController.mode,
          home: HomeShell(themeController: themeController, settings: settings),
        );
      },
    );
  }
}