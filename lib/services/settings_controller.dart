import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/home_layout.dart';
import 'file_service.dart';
import 'output_location.dart';

/// Browsing preferences, saved between launches.
class SettingsController extends ChangeNotifier {
  /// The app-wide settings, so pickers anywhere can read them.
  static SettingsController? current;

  SettingsController() {
    current = this;
  }

  static const _sortKey = 'sort_by';
  static const _hiddenKey = 'show_hidden';
  static const _gridKey = 'grid_view';
  static const _favToolsKey = 'favorite_tools';
  static const _homeOrderKey = 'home_order';
  static const _homeHiddenKey = 'home_hidden';
  static const _quickKey = 'quick_folders';
  static const _longPressKey = 'long_press_ms';
  static const _dragKey = 'drag_select';
  static const _hapticKey = 'haptics';
  static const _animKey = 'animations';
  static const _hapticLevelKey = 'haptic_level';
  static const _outputKey = 'output_mode';
  static const _favFilesKey = 'fav_files';
  static const _openedKey = 'opened_files';

  final List<String> _favFiles = [];
  final List<String> _opened = [];
  int _longPressMs = 400;
  bool _dragSelect = true;
  bool _haptics = true;
  int _hapticStrength = 2;
  bool _animations = true;
  OutputMode _outputMode = OutputMode.smart;

  SortBy _sortBy = SortBy.name;
  bool _showHidden = false;
  bool _gridView = false;
  final Set<String> _favoriteTools = {};
  List<String> _homeOrder = [for (final s in homeSections) s.id];
  final Set<String> _homeHidden = {};
  List<String> _quickFolders = [for (final p in quickPresets) p.path];

  /// How long to hold on a file before it gets selected.
  int get longPressMs => _longPressMs;

  /// Files and folders the person starred, newest first.
  List<String> get favoriteFiles => List.unmodifiable(_favFiles);
  bool isFavorite(String path) => _favFiles.contains(path);

  /// Files opened in Polo, most recent first.
  List<String> get openedFiles => List.unmodifiable(_opened);
  bool get dragSelect => _dragSelect;
  bool get haptics => _haptics;

  /// 1 light, 2 medium, 3 strong.
  int get hapticStrength => _hapticStrength;
  bool get animations => _animations;
  OutputMode get outputMode => _outputMode;

  SortBy get sortBy => _sortBy;
  bool get showHidden => _showHidden;
  bool get gridView => _gridView;
  bool isFavoriteTool(String id) => _favoriteTools.contains(id);

  /// The Home sections in the order they are shown.
  List<String> get homeOrder => List.unmodifiable(_homeOrder);
  bool isHomeHidden(String id) => _homeHidden.contains(id);

  /// Folders in Quick access, relative to the storage root.
  List<String> get quickFolders => List.unmodifiable(_quickFolders);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_sortKey);
    _sortBy = SortBy.values.firstWhere(
      (s) => s.name == saved,
      orElse: () => SortBy.name,
    );
    _showHidden = prefs.getBool(_hiddenKey) ?? false;
    _favFiles
      ..clear()
      ..addAll(prefs.getStringList(_favFilesKey) ?? const []);
    _opened
      ..clear()
      ..addAll(prefs.getStringList(_openedKey) ?? const []);
    _longPressMs = (prefs.getInt(_longPressKey) ?? 400).clamp(250, 1000);
    _dragSelect = prefs.getBool(_dragKey) ?? true;
    _haptics = prefs.getBool(_hapticKey) ?? true;
    _hapticStrength = (prefs.getInt(_hapticLevelKey) ?? 2).clamp(1, 3);
    _animations = prefs.getBool(_animKey) ?? true;
    final om = prefs.getString(_outputKey);
    _outputMode = OutputMode.values.firstWhere((m) => m.name == om, orElse: () => OutputMode.smart);
    _gridView = prefs.getBool(_gridKey) ?? false;
    _favoriteTools
      ..clear()
      ..addAll(prefs.getStringList(_favToolsKey) ?? const []);

    // Home layout. Unknown sections are dropped and new ones added at the end.
    final order = prefs.getStringList(_homeOrderKey) ?? const <String>[];
    final known = {for (final s in homeSections) s.id};
    _homeOrder = [
      ...order.where(known.contains).toSet(),
      ...known.where((id) => !order.contains(id)),
    ];
    _homeHidden
      ..clear()
      ..addAll((prefs.getStringList(_homeHiddenKey) ?? const <String>[]).where(known.contains));
    _quickFolders = prefs.getStringList(_quickKey) ?? [for (final p in quickPresets) p.path];
    notifyListeners();
  }

  Future<void> setSortBy(SortBy value) async {
    if (value == _sortBy) return;
    _sortBy = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortKey, value.name);
  }

  Future<void> toggleFavorite(String path) async {
    if (!_favFiles.remove(path)) _favFiles.insert(0, path);
    notifyListeners();
    (await SharedPreferences.getInstance()).setStringList(_favFilesKey, _favFiles);
  }

  Future<void> addFavorites(Iterable<String> paths) async {
    for (final p in paths) {
      if (!_favFiles.contains(p)) _favFiles.insert(0, p);
    }
    notifyListeners();
    (await SharedPreferences.getInstance()).setStringList(_favFilesKey, _favFiles);
  }

  /// Remembers that [path] was just opened.
  Future<void> noteOpened(String path) async {
    _opened
      ..remove(path)
      ..insert(0, path);
    if (_opened.length > 20) _opened.removeRange(20, _opened.length);
    notifyListeners();
    (await SharedPreferences.getInstance()).setStringList(_openedKey, _opened);
  }

  Future<void> clearOpened() async {
    _opened.clear();
    notifyListeners();
    (await SharedPreferences.getInstance()).remove(_openedKey);
  }

  Future<void> setLongPressMs(int value) async {
    value = value.clamp(250, 1000);
    if (value == _longPressMs) return;
    _longPressMs = value;
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_longPressKey, value);
  }

  Future<void> setDragSelect(bool value) async {
    _dragSelect = value;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_dragKey, value);
  }

  Future<void> setHaptics(bool value) async {
    _haptics = value;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_hapticKey, value);
  }

  Future<void> setHapticStrength(int value) async {
    _hapticStrength = value.clamp(1, 3);
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_hapticLevelKey, _hapticStrength);
  }

  Future<void> setAnimations(bool value) async {
    _animations = value;
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_animKey, value);
  }

  Future<void> setOutputMode(OutputMode value) async {
    _outputMode = value;
    notifyListeners();
    (await SharedPreferences.getInstance()).setString(_outputKey, value.name);
  }

  Future<void> setShowHidden(bool value) async {
    if (value == _showHidden) return;
    _showHidden = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hiddenKey, value);
  }

  Future<void> setGridView(bool value) async {
    if (value == _gridView) return;
    _gridView = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_gridKey, value);
  }

  Future<void> toggleFavoriteTool(String id) async {
    if (!_favoriteTools.remove(id)) _favoriteTools.add(id);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favToolsKey, _favoriteTools.toList());
  }

  Future<void> setHomeOrder(List<String> order) async {
    _homeOrder = List.of(order);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_homeOrderKey, _homeOrder);
  }

  Future<void> setHomeSectionHidden(String id, bool hidden) async {
    if (hidden) {
      _homeHidden.add(id);
    } else {
      _homeHidden.remove(id);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_homeHiddenKey, _homeHidden.toList());
  }

  Future<void> setQuickFolders(List<String> folders) async {
    _quickFolders = List.of(folders);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_quickKey, _quickFolders);
  }

  /// Puts Home back the way it came.
  Future<void> resetHome() async {
    _homeOrder = [for (final s in homeSections) s.id];
    _homeHidden.clear();
    _quickFolders = [for (final p in quickPresets) p.path];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_homeOrderKey);
    await prefs.remove(_homeHiddenKey);
    await prefs.remove(_quickKey);
  }
}
