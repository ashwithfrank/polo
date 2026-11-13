import 'dart:io';

import 'package:flutter/material.dart';

/// A small rounded preview of an image file. Decodes at a reduced size so long
/// lists stay smooth, and shows [fallback] if the image can't be read.
class FileThumb extends StatelessWidget {
  const FileThumb({
    super.key,
    required this.path,
    required this.fallback,
    this.size = 42,
  });

  final String path;
  final Widget fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          cacheWidth: (size * 3).round(),
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => fallback,
        ),
      ),
    );
  }
}