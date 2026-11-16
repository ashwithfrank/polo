import 'package:flutter/material.dart';

import '../services/settings_controller.dart';
import '../tools/tool.dart';
import '../tools/tools_registry.dart';
import '../widgets/motion.dart';
import '../widgets/tool_card.dart';

/// The tools in one group, opened from a card on the Tools tab.
class ToolCategoryScreen extends StatelessWidget {
  const ToolCategoryScreen({super.key, required this.category, required this.settings});

  final ToolCategory category;
  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    final tools = allTools.where((t) => t.category == category).toList()
      ..sort((a, b) => a.comingSoon == b.comingSoon ? 0 : (a.comingSoon ? 1 : -1));

    return Scaffold(
      appBar: AppBar(title: Text(category.label)),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.25,
          ),
          itemCount: tools.length,
          itemBuilder: (context, i) {
            final tool = tools[i];
            return Reveal(
              index: i,
              child: ToolCard(
                tool: tool,
                favorite: settings.isFavoriteTool(tool.id),
                onToggleFavorite: () => settings.toggleFavoriteTool(tool.id),
              ),
            );
          },
        ),
      ),
    );
  }
}