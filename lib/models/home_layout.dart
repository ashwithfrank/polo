import 'package:flutter/material.dart';

/// A block of the Home screen that can be moved or hidden.
class HomeSection {
  const HomeSection(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
}

const homeSections = <HomeSection>[
  HomeSection('storage', 'Storage', Icons.pie_chart_outline),
  HomeSection('vault', 'Vault', Icons.lock_outline),
  HomeSection('categories', 'Categories', Icons.category_outlined),
  HomeSection('quick', 'Quick access', Icons.bolt_outlined),
  HomeSection('favorites', 'Favourites', Icons.star_outline),
  HomeSection('opened', 'Recently opened', Icons.visibility_outlined),
  HomeSection('recent', 'Recent files', Icons.history),
];

HomeSection homeSectionFor(String id) => homeSections.firstWhere((s) => s.id == id);

/// A folder shown in Quick access. [path] is relative to the storage root.
class QuickFolder {
  const QuickFolder(this.path, this.label, this.icon, this.color);

  final String path;
  final String label;
  final IconData icon;
  final Color color;
}

/// The folders Polo offers by default, in their usual order.
const quickPresets = <QuickFolder>[
  QuickFolder('Download', 'Downloads', Icons.download_outlined, Colors.green),
  QuickFolder('DCIM/Camera', 'Camera', Icons.photo_camera_outlined, Colors.pink),
  QuickFolder('Pictures', 'Pictures', Icons.image_outlined, Colors.orange),
  QuickFolder('Documents', 'Documents', Icons.description_outlined, Colors.blue),
  QuickFolder('Music', 'Music', Icons.music_note_outlined, Colors.teal),
  QuickFolder('Movies', 'Movies', Icons.movie_outlined, Colors.deepPurple),
  QuickFolder('Polo', 'Polo', Icons.folder_special_outlined, Colors.deepOrange),
];

bool isPresetFolder(String path) => quickPresets.any((p) => p.path == path);

/// The look of a quick access folder: a preset's own, or a plain folder.
QuickFolder quickFolderFor(String path, Color fallback) {
  for (final p in quickPresets) {
    if (p.path == path) return p;
  }
  final name = path.split('/').where((s) => s.isNotEmpty).lastOrNull ?? path;
  return QuickFolder(path, name, Icons.folder_outlined, fallback);
}
