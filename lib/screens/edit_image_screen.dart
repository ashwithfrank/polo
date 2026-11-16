import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/file_item.dart';
import '../services/file_service.dart';
import '../services/image_edit_service.dart';
import '../widgets/polo_message.dart';
import '../widgets/progress_dialog.dart';

/// Crop, rotate and flip one picture. The result is saved as a new file.
class EditImageScreen extends StatefulWidget {
  const EditImageScreen({super.key, required this.item});

  final FileItem item;

  @override
  State<EditImageScreen> createState() => _EditImageScreenState();
}

class _EditImageScreenState extends State<EditImageScreen> {
  final _service = EditImageService(FileService());

  late final ImageProvider _provider = ResizeImage(
    FileImage(File(widget.item.path)),
    width: 1600,
  );
  ImageStream? _stream;
  ImageStreamListener? _listener;

  Size? _imageSize;
  bool _failed = false;

  int _turns = 0;
  bool _flipH = false;
  bool _flipV = false;
  double? _aspect; // width / height, or null for free
  Rect _crop = const Rect.fromLTRB(0, 0, 1, 1); // fractions of the shown picture
  bool _saving = false;

  static const _aspects = <({String label, double? value})>[
    (label: 'Free', value: null),
    (label: '1:1', value: 1),
    (label: '4:3', value: 4 / 3),
    (label: '3:4', value: 3 / 4),
    (label: '3:2', value: 3 / 2),
    (label: '2:3', value: 2 / 3),
    (label: '16:9', value: 16 / 9),
    (label: '9:16', value: 9 / 16),
  ];

  @override
  void initState() {
    super.initState();
    _stream = _provider.resolve(ImageConfiguration.empty);
    _listener = ImageStreamListener(
          (info, _) {
        if (!mounted) return;
        setState(() {
          _imageSize = Size(info.image.width.toDouble(), info.image.height.toDouble());
        });
      },
      onError: (_, _) {
        if (mounted) setState(() => _failed = true);
      },
    );
    _stream!.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    super.dispose();
  }

  /// The size of the picture as it is shown, after turning.
  Size? get _shown {
    final s = _imageSize;
    if (s == null) return null;
    return _turns.isOdd ? Size(s.height, s.width) : s;
  }

  void _setAspect(double? value) {
    final shown = _shown;
    setState(() {
      _aspect = value;
      if (value == null || shown == null) return;
      final boxAspect = shown.width / shown.height;
      final double w;
      final double h;
      if (value >= boxAspect) {
        w = 1;
        h = boxAspect / value;
      } else {
        h = 1;
        w = value / boxAspect;
      }
      _crop = Rect.fromLTWH((1 - w) / 2, (1 - h) / 2, w, h);
    });
  }

  void _turn(int by) {
    setState(() {
      _turns = (_turns + by) % 4;
      _crop = const Rect.fromLTRB(0, 0, 1, 1);
    });
    if (_aspect != null) _setAspect(_aspect);
  }

  void _reset() {
    setState(() {
      _turns = 0;
      _flipH = false;
      _flipV = false;
      _aspect = null;
      _crop = const Rect.fromLTRB(0, 0, 1, 1);
    });
  }

  EditPlan get _plan => EditPlan(
    quarterTurns: _turns,
    flipHorizontal: _flipH,
    flipVertical: _flipV,
    cropLeft: _crop.left,
    cropTop: _crop.top,
    cropRight: _crop.right,
    cropBottom: _crop.bottom,
  );

  Future<void> _save() async {
    final plan = _plan;
    if (plan.isEmpty) {
      showPoloMessage(context, 'Crop, rotate or flip first');
      return;
    }
    setState(() => _saving = true);
    try {
      final out = await runWithProgress(
        context,
        'Saving…',
            () => _service.edit(widget.item, plan),
      );
      if (!mounted) return;
      showPoloMessage(context, 'Saved as ${out.name}');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showPoloMessage(
        context,
        e is FormatException ? e.message : "Couldn't save this picture",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = _shown;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit image'),
        actions: [
          IconButton(
            tooltip: 'Reset',
            icon: const Icon(Icons.restart_alt),
            onPressed: _saving ? null : _reset,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _failed
                ? const Center(child: Text("Couldn't open this picture"))
                : shown == null
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
              builder: (context, c) {
                const pad = 16.0;
                final maxW = math.max(c.maxWidth - pad * 2, 1);
                final maxH = math.max(c.maxHeight - pad * 2, 1);
                final scale = math.min(maxW / shown.width, maxH / shown.height);
                final size = Size(shown.width * scale, shown.height * scale);
                return Center(
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Transform.flip(
                          flipX: _flipH,
                          flipY: _flipV,
                          child: RotatedBox(
                            quarterTurns: _turns,
                            child: Image(
                              image: _provider,
                              fit: BoxFit.fill,
                              gaplessPlayback: true,
                            ),
                          ),
                        ),
                        _CropOverlay(
                          size: size,
                          crop: _crop,
                          aspect: _aspect,
                          onChanged: (r) => setState(() => _crop = r),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Rotate left',
                icon: const Icon(Icons.rotate_left),
                onPressed: _saving ? null : () => _turn(3),
              ),
              IconButton(
                tooltip: 'Rotate right',
                icon: const Icon(Icons.rotate_right),
                onPressed: _saving ? null : () => _turn(1),
              ),
              IconButton(
                tooltip: 'Flip left-right',
                icon: Icon(Icons.flip, color: _flipH ? scheme.primary : null),
                onPressed: _saving ? null : () => setState(() => _flipH = !_flipH),
              ),
              IconButton(
                tooltip: 'Flip top-bottom',
                icon: Transform.rotate(
                  angle: math.pi / 2,
                  child: Icon(Icons.flip, color: _flipV ? scheme.primary : null),
                ),
                onPressed: _saving ? null : () => setState(() => _flipV = !_flipV),
              ),
            ],
          ),
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _aspects.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final a = _aspects[i];
                return ChoiceChip(
                  label: Text(a.label),
                  selected: _aspect == a.value,
                  onSelected: _saving ? null : (_) => _setAspect(a.value),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _saving || shown == null ? null : _save,
                child: const Text('Save as a new picture'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Grab { none, move, topLeft, topRight, bottomLeft, bottomRight }

/// The crop frame: drag inside to move it, drag a corner to resize.
class _CropOverlay extends StatefulWidget {
  const _CropOverlay({
    required this.size,
    required this.crop,
    required this.aspect,
    required this.onChanged,
  });

  final Size size;
  final Rect crop; // fractions
  final double? aspect;
  final ValueChanged<Rect> onChanged;

  @override
  State<_CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<_CropOverlay> {
  static const _minSide = 48.0;
  static const _grabRadius = 40.0;

  _Grab _grab = _Grab.none;
  Rect _startRect = Rect.zero;
  Offset _anchor = Offset.zero;
  Offset _startPoint = Offset.zero;

  Rect get _px => Rect.fromLTRB(
    widget.crop.left * widget.size.width,
    widget.crop.top * widget.size.height,
    widget.crop.right * widget.size.width,
    widget.crop.bottom * widget.size.height,
  );

  void _emit(Rect px) {
    final w = widget.size.width;
    final h = widget.size.height;
    widget.onChanged(
      Rect.fromLTRB(
        (px.left / w).clamp(0.0, 1.0).toDouble(),
        (px.top / h).clamp(0.0, 1.0).toDouble(),
        (px.right / w).clamp(0.0, 1.0).toDouble(),
        (px.bottom / h).clamp(0.0, 1.0).toDouble(),
      ),
    );
  }

  void _start(DragStartDetails d) {
    final r = _px;
    final p = d.localPosition;
    final corners = {
      _Grab.topLeft: r.topLeft,
      _Grab.topRight: r.topRight,
      _Grab.bottomLeft: r.bottomLeft,
      _Grab.bottomRight: r.bottomRight,
    };

    _Grab best = _Grab.none;
    var bestDistance = _grabRadius;
    corners.forEach((grab, corner) {
      final distance = (corner - p).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = grab;
      }
    });

    _startRect = r;
    _startPoint = p;
    if (best != _Grab.none) {
      _grab = best;
      _anchor = switch (best) {
        _Grab.topLeft => r.bottomRight,
        _Grab.topRight => r.bottomLeft,
        _Grab.bottomLeft => r.topRight,
        _ => r.topLeft,
      };
    } else if (r.contains(p)) {
      _grab = _Grab.move;
    } else {
      _grab = _Grab.none;
    }
  }

  void _update(DragUpdateDetails d) {
    if (_grab == _Grab.none) return;
    final w = widget.size.width;
    final h = widget.size.height;
    final p = Offset(
      d.localPosition.dx.clamp(0.0, w).toDouble(),
      d.localPosition.dy.clamp(0.0, h).toDouble(),
    );

    if (_grab == _Grab.move) {
      final delta = d.localPosition - _startPoint;
      final dx = delta.dx.clamp(-_startRect.left, w - _startRect.right).toDouble();
      final dy = delta.dy.clamp(-_startRect.top, h - _startRect.bottom).toDouble();
      _emit(_startRect.shift(Offset(dx, dy)));
      return;
    }

    final sx = p.dx >= _anchor.dx ? 1.0 : -1.0;
    final sy = p.dy >= _anchor.dy ? 1.0 : -1.0;
    final availW = sx > 0 ? w - _anchor.dx : _anchor.dx;
    final availH = sy > 0 ? h - _anchor.dy : _anchor.dy;

    final a = widget.aspect;
    double width;
    double height;
    if (a == null) {
      width = (p.dx - _anchor.dx).abs().clamp(_minSide, math.max(availW, _minSide)).toDouble();
      height = (p.dy - _anchor.dy).abs().clamp(_minSide, math.max(availH, _minSide)).toDouble();
    } else {
      width = math.max((p.dx - _anchor.dx).abs(), (p.dy - _anchor.dy).abs() * a);
      final limit = math.min(availW, availH * a);
      width = width.clamp(math.min(_minSide, limit), math.max(limit, 1.0)).toDouble();
      height = width / a;
    }
    _emit(Rect.fromPoints(_anchor, _anchor + Offset(sx * width, sy * height)));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: _start,
      onPanUpdate: _update,
      onPanEnd: (_) => _grab = _Grab.none,
      child: CustomPaint(
        size: widget.size,
        painter: _CropPainter(_px),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.rect);

  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    // Dim everything outside the crop.
    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(rect);
    canvas.drawPath(dim, Paint()..color = Colors.black54);

    // Thirds guide.
    final guide = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = rect.left + rect.width * i / 3;
      final y = rect.top + rect.height * i / 3;
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), guide);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), guide);
    }

    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Corner handles.
    final handle = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const len = 22.0;
    void corner(Offset c, double dx, double dy) {
      canvas.drawLine(c, c + Offset(dx * len, 0), handle);
      canvas.drawLine(c, c + Offset(0, dy * len), handle);
    }

    corner(rect.topLeft, 1, 1);
    corner(rect.topRight, -1, 1);
    corner(rect.bottomLeft, 1, -1);
    corner(rect.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.rect != rect;
}