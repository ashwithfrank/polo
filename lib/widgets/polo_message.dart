import 'dart:async';

import 'package:flutter/material.dart';

import 'motion.dart';

/// Polo's own replacement for the snackbar. A small ball pops up at the bottom
/// centre, stretches out to the left and right into the message, stays for a
/// few seconds, then folds back into a ball and disappears.
///
/// Only one message shows at a time; a new one replaces the current one.
void showPoloMessage(
    BuildContext context,
    String message, {
      String? actionLabel,
      VoidCallback? onAction,
    }) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _current?.remove();
  _current = null;

  final scheme = Theme.of(context).colorScheme;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _PoloMessage(
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
      background: scheme.inverseSurface,
      foreground: scheme.onInverseSurface,
      accent: scheme.inversePrimary,
      onDone: () {
        if (identical(_current, entry)) _current = null;
        entry.remove();
      },
    ),
  );
  _current = entry;
  overlay.insert(entry);
}

OverlayEntry? _current;

class _PoloMessage extends StatefulWidget {
  const _PoloMessage({
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.background,
    required this.foreground,
    required this.accent,
    required this.onDone,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color background;
  final Color foreground;
  final Color accent;
  final VoidCallback onDone;

  @override
  State<_PoloMessage> createState() => _PoloMessageState();
}

class _PoloMessageState extends State<_PoloMessage> with SingleTickerProviderStateMixin {
  static const _ball = 48.0;

  late final AnimationController _controller = AnimationController(vsync: this);
  late final Animation<double> _pop = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.3, curve: Curves.easeOutBack),
    reverseCurve: const Interval(0.0, 0.3, curve: Curves.easeInBack),
  );
  late final Animation<double> _rise = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.3, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _stretch = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.3, 0.85, curve: Curves.easeInOutCubic),
  );
  late final Animation<double> _content = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
  );

  Timer? _timer;
  bool _closing = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _controller.duration = motion(context, 650);
    _controller.forward().whenComplete(() {
      if (!mounted || _closing) return;
      final seconds = widget.actionLabel == null ? 3 : 5;
      _timer = Timer(Duration(seconds: seconds), _close);
    });
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    await _controller.reverse();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    // Sits above the bottom navigation bar, or above the keyboard.
    final bottom = keyboard > 0 ? keyboard + 16 : media.padding.bottom + 92;
    final maxWidth = media.size.width - 32;

    final text = Text(
      widget.message,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: widget.foreground, fontSize: 14),
    );

    return Positioned(
      left: 16,
      right: 16,
      bottom: bottom,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Semantics(
          liveRegion: true,
          label: widget.message,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(_rise),
            child: ScaleTransition(
              scale: _pop,
              child: GestureDetector(
                onTap: _close,
                onVerticalDragEnd: (_) => _close(),
                child: Material(
                  color: widget.background,
                  elevation: 4,
                  shape: const StadiumBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: _ball, minHeight: _ball),
                    child: SizeTransition(
                      axis: Axis.horizontal,
                      alignment: Alignment.center,
                      sizeFactor: _stretch,
                      child: FadeTransition(
                        opacity: _content,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxWidth),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              20,
                              12,
                              widget.actionLabel == null ? 20 : 8,
                              12,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(child: text),
                                if (widget.actionLabel != null) ...[
                                  const SizedBox(width: 8),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      foregroundColor: widget.accent,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: () {
                                      widget.onAction?.call();
                                      _close();
                                    },
                                    child: Text(widget.actionLabel!),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}