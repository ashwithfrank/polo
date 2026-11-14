import 'package:flutter/material.dart';

import '../models/storage_category.dart';
import '../services/settings_controller.dart';
import '../services/storage_controller.dart';
import '../services/trash_service.dart';
import '../theme/theme_controller.dart';
import 'browse_screen.dart';
import 'category_screen.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'storage_screen.dart';
import 'tools_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.themeController,
    required this.settings,
  });

  final ThemeController themeController;
  final SettingsController settings;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  final _storage = StorageController();
  final _jump = ValueNotifier<String?>(null);
  int _index = 0;

  static const _titles = ['Polo', 'Browse', 'Tools', 'Storage'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _storage.load();
    // Clear out trash older than 30 days. Best effort.
    TrashService().purgeOld().catchError((_) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _storage.dispose();
    _jump.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may have just granted access in system settings.
    if (state == AppLifecycleState.resumed && _storage.needsAccess) {
      _storage.load();
    }
  }

  void _select(int i) {
    // Files may have changed while the user was in Browse or Tools.
    if (_index == 1 || _index == 2) _storage.markStale();
    setState(() => _index = i);
    if (i == 0 || i == 3) _storage.loadIfStale();
  }

  void _openFolder(String path) {
    _select(1);
    _jump.value = path;
  }

  void _openSearch() {
    _storage.loadIfStale();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => SearchScreen(
          controller: _storage,
          onOpenFolder: (path) {
            Navigator.of(routeContext).pop();
            _openFolder(path);
          },
        ),
      ),
    );
  }

  void _openCategory(StorageCategory category) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => CategoryScreen(
          controller: _storage,
          category: category,
          onShowInFolder: (path) {
            Navigator.of(routeContext).pop();
            _openFolder(path);
          },
        ),
      ),
    );
  }

  void _toggleTheme(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    widget.themeController.setMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _titles[_index],
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: _openSearch,
          ),
          IconButton(
            tooltip: isDark ? 'Switch to light theme' : 'Switch to dark theme',
            icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () => _toggleTheme(context),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SettingsScreen(
                  themeController: widget.themeController,
                  settings: widget.settings,
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(
            controller: _storage,
            onOpenFolder: _openFolder,
            onOpenStorage: () => _select(3),
            onSearch: _openSearch,
            onOpenCategory: _openCategory,
          ),
          BrowseScreen(active: _index == 1, jumpTo: _jump, settings: widget.settings),
          const ToolsScreen(),
          StorageScreen(controller: _storage, onOpenCategory: _openCategory),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Browse',
          ),
          NavigationDestination(
            icon: Icon(Icons.handyman_outlined),
            selectedIcon: Icon(Icons.handyman),
            label: 'Tools',
          ),
          NavigationDestination(
            icon: Icon(Icons.pie_chart_outline),
            selectedIcon: Icon(Icons.pie_chart),
            label: 'Storage',
          ),
        ],
      ),
    );
  }
}