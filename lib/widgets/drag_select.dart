import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'haptics.dart';
import '../services/settings_controller.dart';

/// Wraps a list or grid so that holding on an item selects it, and then
/// sliding the finger up or down keeps selecting (or un-selecting) every item
/// it passes. Wrap each row in a [DragSelectItem].
class DragSelectArea extends StatefulWidget {
  const DragSelectArea({
    super.key,
    required this.order,
    required this.selected,
    required this.onChanged,
    required this.scroll,
    this.holdFor,
    this.drag,
    required this.child,
  });

  /// Paths in the order they are shown.
  final List<String> order;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  /// How long to hold before selecting starts. Null follows Settings.
  final Duration? holdFor;

  /// The list's scroll controller, used to scroll while dragging near an edge.
  final ScrollController scroll;

  /// When false, holding only selects the one item. Null follows Settings.
  final bool? drag;
  final Widget child;

  @override
  State<DragSelectArea> createState() => _DragSelectAreaState();
}

class _DragSelectAreaState extends State<DragSelectArea> {
  final Map<String, BuildContext> _items = {};
  Set<String> _base = {};
  bool _adding = true;
  int _anchor = -1;
  int _last = -1;
  Offset _pos = Offset.zero;
  Timer? _scroller;

  bool get _drag => widget.drag ?? SettingsController.current?.dragSelect ?? true;
  Duration get _hold =>
      widget.holdFor ?? Duration(milliseconds: SettingsController.current?.longPressMs ?? 400);

  void _register(String path, BuildContext c) => _items[path] = c;
  void _unregister(String path, BuildContext c) {
    if (_items[path] == c) _items.remove(path);
  }

  String? _pathAt(Offset global) {
    for (final e in _items.entries) {
      final box = e.value.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(global)) return e.key;
    }
    return null;
  }

  void _apply(int a, int b) {
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    final next = Set<String>.of(_base);
    for (var i = lo; i <= hi && i < widget.order.length; i++) {
      if (_adding) {
        next.add(widget.order[i]);
      } else {
        next.remove(widget.order[i]);
      }
    }
    widget.onChanged(next);
  }

  void _start(LongPressStartDetails d) {
    _pos = d.globalPosition;
    final path = _pathAt(_pos);
    if (path == null) return;
    _anchor = widget.order.indexOf(path);
    if (_anchor < 0) return;
    _last = _anchor;
    _base = Set.of(widget.selected);
    _adding = !_base.contains(path);
    Haptics.strong();
    _apply(_anchor, _anchor);
    if (_drag) {
      _scroller = Timer.periodic(const Duration(milliseconds: 16), (_) => _autoScroll());
    }
  }

  void _move(LongPressMoveUpdateDetails d) {
    if (_anchor < 0 || !_drag) return;
    _pos = d.globalPosition;
    _update();
  }

  void _update() {
    final path = _pathAt(_pos);
    if (path == null) return;
    final i = widget.order.indexOf(path);
    if (i < 0 || i == _last) return;
    _last = i;
    Haptics.select();
    _apply(_anchor, i);
  }

  void _autoScroll() {
    if (!mounted || !widget.scroll.hasClients) return;
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    const edge = 72.0;
    double speed = 0;
    if (_pos.dy < top + edge) {
      speed = -(top + edge - _pos.dy) / edge * 14;
    } else if (_pos.dy > bottom - edge) {
      speed = (_pos.dy - (bottom - edge)) / edge * 14;
    }
    if (speed == 0) return;
    final p = widget.scroll.position;
    final to = (p.pixels + speed).clamp(p.minScrollExtent, p.maxScrollExtent);
    if (to == p.pixels) return;
    widget.scroll.jumpTo(to);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _update();
    });
  }

  void _end() {
    _scroller?.cancel();
    _scroller = null;
    _anchor = -1;
  }

  @override
  void dispose() {
    _scroller?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Scope(
      state: this,
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: {
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(duration: _hold),
            (r) {
              r
                ..onLongPressStart = _start
                ..onLongPressMoveUpdate = _move
                ..onLongPressEnd = ((_) => _end())
                ..onLongPressCancel = _end;
            },
          ),
        },
        child: widget.child,
      ),
    );
  }
}

class _Scope extends InheritedWidget {
  const _Scope({required this.state, required super.child});

  final _DragSelectAreaState state;

  @override
  bool updateShouldNotify(_Scope old) => false;
}

/// Marks one row or tile as selectable by [DragSelectArea].
class DragSelectItem extends StatefulWidget {
  const DragSelectItem({super.key, required this.path, required this.child});

  final String path;
  final Widget child;

  @override
  State<DragSelectItem> createState() => _DragSelectItemState();
}

class _DragSelectItemState extends State<DragSelectItem> {
  _DragSelectAreaState? _area;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _area?._unregister(widget.path, context);
    _area = context.dependOnInheritedWidgetOfExactType<_Scope>()?.state;
    _area?._register(widget.path, context);
  }

  @override
  void didUpdateWidget(DragSelectItem old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _area?._unregister(old.path, context);
      _area?._register(widget.path, context);
    }
  }

  @override
  void dispose() {
    _area?._unregister(widget.path, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
