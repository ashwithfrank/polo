import 'package:flutter/material.dart';

import '../services/settings_controller.dart';
import '../tools/tool.dart';
import '../widgets/motion.dart';
import '../tools/tools_registry.dart';

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

  Widget _grid(List<Tool> tools) {
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
            child: _ToolCard(
              tool: tool,
              favorite: widget.settings.isFavoriteTool(tool.id),
              onToggleFavorite: () => widget.settings.toggleFavoriteTool(tool.id),
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

        if (found.isEmpty) {
          slivers.add(
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('No tools match your search')),
            ),
          );
        } else if (searching) {
          // One flat list while searching.
          slivers
            ..add(const SliverToBoxAdapter(child: SizedBox(height: 16)))
            ..add(_grid([...ready, ...soon]));
        } else {
          final favorites = ready.where((t) => widget.settings.isFavoriteTool(t.id)).toList();
          if (favorites.isNotEmpty) {
            slivers
              ..add(_header(context, 'Favorites'))
              ..add(_grid(favorites));
          }
          for (final category in ToolCategory.values) {
            final inCategory = ready.where((t) => t.category == category).toList();
            if (inCategory.isEmpty) continue;
            slivers
              ..add(_header(context, category.label))
              ..add(_grid(inCategory));
          }
          if (soon.isNotEmpty) {
            slivers
              ..add(_header(context, 'Coming soon'))
              ..add(_grid(soon));
          }
        }
        slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));

        return CustomScrollView(slivers: slivers);
      },
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.tool,
    required this.favorite,
    required this.onToggleFavorite,
  });

  final Tool tool;
  final bool favorite;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = !tool.comingSoon;

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: PressScale(
        child: Material(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? () => tool.run!(context) : null,
            onLongPress: enabled ? onToggleFavorite : null,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(tool.icon, color: scheme.primary),
                      ),
                      const Spacer(),
                      Text(
                        tool.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        enabled ? tool.subtitle : 'Coming soon',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                if (enabled)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IconButton(
                      tooltip: favorite ? 'Remove from favorites' : 'Add to favorites',
                      visualDensity: VisualDensity.compact,
                      icon: AnimatedSwitcher(
                        duration: motion(context, 220),
                        switchInCurve: Curves.easeOutBack,
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(scale: animation, child: child),
                        child: Icon(
                          favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                          key: ValueKey(favorite),
                          size: 22,
                          color: favorite
                              ? scheme.primary
                              : scheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                      onPressed: onToggleFavorite,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}