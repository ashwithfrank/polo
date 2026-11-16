import 'package:flutter/material.dart';

enum ToolCategory {
  convert('Convert', Icons.swap_horiz, 'Change file formats'),
  images('Images', Icons.image_outlined, 'Edit, shrink and inspect'),
  documents('PDF and documents', Icons.picture_as_pdf_outlined, 'Merge, split and create'),
  organize('Organize', Icons.drive_file_rename_outline, 'Rename, zip and sort'),
  cleanup('Clean up', Icons.cleaning_services_outlined, 'Free up space'),
  developer('Developer', Icons.code, 'Format, encode and inspect'),
  privacy('Privacy', Icons.shield_outlined, 'Protect your files');

  const ToolCategory(this.label, this.icon, this.blurb);
  final String label;
  final IconData icon;
  final String blurb;
}

/// One entry in the Tools tab. A tool with no [run] is shown as "Coming soon".
class Tool {
  const Tool({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.category,
    this.keywords = const [],
    this.run,
  });

  /// Stable, never changes: used to save favourites.
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final ToolCategory category;

  /// Extra words that search should match, e.g. "compress" for the zip tool.
  final List<String> keywords;
  final Future<void> Function(BuildContext context)? run;

  bool get comingSoon => run == null;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q) ||
        subtitle.toLowerCase().contains(q) ||
        keywords.any((k) => k.toLowerCase().contains(q));
  }
}