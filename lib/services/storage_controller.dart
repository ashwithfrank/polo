import 'package:flutter/foundation.dart';

import '../models/file_item.dart';
import '../models/storage_category.dart';
import 'storage_access.dart';
import 'storage_info.dart';
import 'storage_scanner.dart';

/// Shared by the Home and Storage screens so the scan only runs once.
class StorageController extends ChangeNotifier {
  StorageInfo? info;
  ScanResult? scan;
  bool loading = false;
  bool needsAccess = false;
  String? error;

  DateTime? _lastLoaded;
  bool _disposed = false;

  void markStale() => _lastLoaded = null;

  /// Reloads only if the data is older than [maxAge].
  Future<void> loadIfStale({Duration maxAge = const Duration(minutes: 1)}) async {
    final last = _lastLoaded;
    if (last != null && DateTime.now().difference(last) < maxAge) return;
    await load();
  }

  Future<void> load() async {
    if (loading) return;
    loading = true;
    error = null;
    _notify();

    if (!await StorageAccess.isGranted()) {
      needsAccess = true;
      loading = false;
      _notify();
      return;
    }
    needsAccess = false;

    info = await StorageInfo.read();
    _notify();

    try {
      scan = await StorageScanner.scan();
      _lastLoaded = DateTime.now();
    } catch (_) {
      error = "Couldn't scan your files";
    }

    loading = false;
    _notify();
  }

  Future<void> requestAccess() async {
    await StorageAccess.request();
    await load();
  }

  /// Removes a deleted file from the current results right away, so lists
  /// update without waiting for a full rescan.
  void forget(FileItem item) {
    final s = scan;
    if (s == null) return;
    s.index.removeWhere((i) => i.path == item.path);
    s.recent.removeWhere((i) => i.path == item.path);
    s.largest.removeWhere((i) => i.path == item.path);

    final category = StorageCategory.of(item.kind);
    s.bytes[category] = (s.bytes[category] ?? 0) - item.size;
    s.counts[category] = (s.counts[category] ?? 0) - 1;

    final i = info;
    if (i != null) info = StorageInfo(total: i.total, free: i.free + item.size);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}