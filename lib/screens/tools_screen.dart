import 'package:flutter/material.dart';

import '../services/settings_controller.dart';
import '../tools/tool.dart';
import '../tools/tools_registry.dart';
import '../widgets/motion.dart';
import '../widgets/tool_card.dart';
import 'tool_category_screen.dart';

/// The Tools tab: one card per kind of tool. Tapping a card opens that
/// group's tools. Searching shows matching tools from every group at once.
class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key, required this.settings});

  final SettingsController settings;

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Widget _header(BuildContext context, String text) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _toolGrid(List<Tool> tools) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid.builder(
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
              favorite: widget.settings.isFavoriteTool(tool.id),
              onToggleFavorite: () => widget.settings.toggleFavoriteTool(tool.id),
            ),
          );
        },
      ),
    );
  }

  Widget _categoryGrid(List<ToolCategory> categories) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.05,
        ),
        itemCount: categories.length,
        itemBuilder: (context, i) {
          final category = categories[i];
          final count =
              allTools.where((t) => t.category == category && !t.comingSoon).length;
          return Reveal(
            index: i,
            child: _CategoryCard(
              category: category,
              count: count,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ToolCategoryScreen(category: category, settings: widget.settings),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        final searching = _query.trim().isNotEmpty;
        final found = allTools.where((t) => t.matches(_query)).toList();
        final ready = found.where((t) => !t.comingSoon).toList();
        final soon = found.where((t) => t.comingSoon).toList();

        final slivers = <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search tools',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: searching
                      ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  )
                      : null,
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
            ),
          ),
        ];

        if (searching) {
          if (found.isEmpty) {
            slivers.add(
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('No tools match your search')),
              ),
            );
          } else {
            slivers
              ..add(const SliverToBoxAdapter(child: SizedBox(height: 16)))
              ..add(_toolGrid([...ready, ...soon]));
          }
        } else {
          final favorites = ready.where((t) => widget.settings.isFavoriteTool(t.id)).toList();
          if (favorites.isNotEmpty) {
            slivers
              ..add(_header(context, 'Favorites'))
              ..add(_toolGrid(favorites));
          }
          final categories = [
            for (final c in ToolCategory.values)
              if (allTools.any((t) => t.category == c)) c,
          ];
          slivers
            ..add(_header(context, 'All tools'))
            ..add(_categoryGrid(categories));
        }
        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));

        return CustomScrollView(slivers: slivers);
      },
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.count, required this.onTap});

  final ToolCategory category;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PressScale(
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(category.icon, color: scheme.primary, size: 26),
                ),
                const Spacer(),
                Text(
                  category.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(height: 2),
                Text(
                  category.blurb,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$count ${count == 1 ? 'tool' : 'tools'}',
                  style: TextStyle(fontSize: 12, color: scheme.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}