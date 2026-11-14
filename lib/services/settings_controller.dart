import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'file_service.dart';

/// Browsing preferences, saved between launches.
class SettingsController extends ChangeNotifier {
  static const _sortKey = 'sort_by';
  static const _hiddenKey = 'show_hidden';
  static const _gridKey = 'grid_view';

  SortBy _sortBy = SortBy.name;
  bool _showHidden = false;
  bool _gridView = false;

  SortBy get sortBy => _sortBy;
  bool get showHidden => _showHidden;
  bool get gridView => _gridView;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_sortKey);
    _sortBy = SortBy.values.firstWhere(
          (s) => s.name == saved,
      orElse: () => SortBy.name,
    );
    _showHidden = prefs.getBool(_hiddenKey) ?? false;
    _gridView = prefs.getBool(_gridKey) ?? false;
    notifyListeners();
  }

  Future<void> setSortBy(SortBy value) async {
    if (value == _sortBy) return;
    _sortBy = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortKey, value.name);
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
}