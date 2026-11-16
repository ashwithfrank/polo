import 'package:flutter/material.dart';

import '../tools/tool.dart';
import 'motion.dart';

/// A tool tile: icon, name, one-line description and a favourite star.
class ToolCard extends StatelessWidget {
  const ToolCard({
    super.key,
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