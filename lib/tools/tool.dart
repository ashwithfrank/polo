import 'package:flutter/material.dart';

enum ToolCategory {
  convert('Convert'),
  documents('PDF and documents'),
  organize('Organize'),
  cleanup('Clean up'),
  developer('Developer'),
  privacy('Privacy');

  const ToolCategory(this.label);
  final String label;
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