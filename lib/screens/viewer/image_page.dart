import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/file_item.dart';
import '../../widgets/open_external.dart';

/// Decodes images at about twice the screen width: sharp when zoomed, without
/// holding a full 12 megapixel photo in memory.
ImageProvider viewerImageFor(BuildContext context, FileItem item) {
  final width = (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context) * 2)
      .round()
      .clamp(1080, 2800);
  return ResizeImage(FileImage(File(item.path)), width: width);
}

class ImagePage extends StatefulWidget {
  const ImagePage({
    super.key,
    required this.item,
    required this.onZoomChanged,
    required this.onTap,
  });

  final FileItem item;
  final ValueChanged<bool> onZoomChanged;

  /// A single tap, used to show or hide the viewer's bars.
  final VoidCallback onTap;

  @override
  State<ImagePage> createState() => _ImagePageState();
}

class _ImagePageState extends State<ImagePage> {
  final _transform = TransformationController();
  Offset _doubleTapAt = Offset.zero;

  @override
  void initState() {
    super.initState();
    _transform.addListener(() {
      widget.onZoomChanged(_transform.value.getMaxScaleOnAxis() > 1.05);
    });
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    if (_transform.value.getMaxScaleOnAxis() > 1.05) {
      _transform.value = Matrix4.identity();
    } else {
      const scale = 2.5;
      final p = _doubleTapAt;
      _transform.value =
          Matrix4.translationValues(-p.dx * (scale - 1), -p.dy * (scale - 1), 0) *
              Matrix4.diagonal3Values(scale, scale, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 6,
        child: SizedBox.expand(
          child: Image(
            image: viewerImageFor(context, widget.item),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, sync) => sync
                ? child
                : AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 180),
              child: child,
            ),
            errorBuilder: (context, _, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.broken_image_outlined, color: Colors.white70, size: 56),
                    const SizedBox(height: 12),
                    const Text(
                      "Polo can't show this image",
                      style: TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => openExternally(context, widget.item),
                      child: const Text('Open with another app'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}