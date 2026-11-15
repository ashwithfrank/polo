import 'package:flutter/material.dart';

import 'motion.dart';

class SelectionAction {
  const SelectionAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
}

/// The row of actions along the bottom while files are selected.
class SelectionActionBar extends StatelessWidget {
  const SelectionActionBar({super.key, required this.actions});

  final List<SelectionAction> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motion(context, 220),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) =>
          FractionalTranslation(translation: Offset(0, 1 - v), child: child),
      child: Material(
        color: scheme.surfaceContainerHighest,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                for (final a in actions)
                  Expanded(
                    child: InkWell(
                      onTap: a.onTap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(a.icon, color: a.color ?? scheme.onSurface),
                            const SizedBox(height: 2),
                            Text(
                              a.label,
                              style: TextStyle(fontSize: 11, color: a.color ?? scheme.onSurface),
                            ),
                          ],
                        ),
                      ),
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