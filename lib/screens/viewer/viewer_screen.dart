import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/file_item.dart';
import '../../widgets/delete_file.dart';
import '../../widgets/file_details.dart';
import '../../widgets/open_external.dart';
import 'audio_page.dart';
import 'image_page.dart';
import 'pdf_page.dart';
import 'text_page.dart';
import 'video_page.dart';

const _textExtensions = {
  'txt', 'md', 'csv', 'log', 'json', 'xml', 'html', 'htm', 'css', 'js', 'ts',
  'dart', 'java', 'kt', 'py', 'sh', 'yaml', 'yml', 'ini', 'conf', 'cfg',
  'properties', 'srt', 'gradle', 'toml', 'sql', 'c', 'cpp', 'h', 'rs', 'go',
};

bool _isText(FileItem item) => _textExtensions.contains(item.extension);

/// Whether Polo can show [item] itself.
bool canView(FileItem item) {
  if (item.isDirectory) return false;
  return switch (item.kind) {
    FileKind.image || FileKind.video || FileKind.audio || FileKind.pdf => true,
    _ => _isText(item),
  };
}

/// One screen for everything Polo can show: images (swipe through a folder),
/// video, audio, PDF and plain text.
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.onDeleted,
  });

  final List<FileItem> items;
  final int initialIndex;
  final void Function(FileItem item)? onDeleted;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  late final List<FileItem> _items = List.of(widget.items);
  late final PageController _pager = PageController(
    initialPage: widget.initialIndex < 0 ? 0 : widget.initialIndex,
  );
  late int _index = widget.initialIndex < 0 ? 0 : widget.initialIndex;
  bool _zoomed = false;

  /// Whether the top bar and the system bars are showing. Images and videos
  /// hide them so the picture fills the whole screen.
  bool _chrome = true;

  FileItem get _current => _items[_index];
  bool get _dark => _current.kind == FileKind.image || _current.kind == FileKind.video;

  bool get _immersive => _dark;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _precacheAround(_index);
    });
  }

  @override
  void dispose() {
    _pager.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    super.dispose();
  }

  void _setChrome(bool visible) {
    if (visible == _chrome) return;
    setState(() => _chrome = visible);
    SystemChrome.setEnabledSystemUIMode(
      visible ? SystemUiMode.manual : SystemUiMode.immersiveSticky,
      overlays: visible ? SystemUiOverlay.values : null,
    );
  }

  /// Decodes the neighbouring images ahead of time so swiping feels instant.
  void _precacheAround(int index) {
    for (final i in [index - 1, index + 1]) {
      if (i < 0 || i >= _items.length || _items[i].kind != FileKind.image) continue;
      precacheImage(viewerImageFor(context, _items[i]), context, onError: (_, _) {});
    }
  }

  Future<void> _delete() async {
    final item = _current;
    final moved = await deleteFileWithConfirm(context, item);
    if (!moved || !mounted) return;
    widget.onDeleted?.call(item);

    if (_items.length == 1) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _items.removeAt(_index);
      if (_index >= _items.length) _index = _items.length - 1;
      _zoomed = false;
    });
    // Keep the pager on the same slot after the list shrinks.
    if (_pager.hasClients) _pager.jumpToPage(_index);
  }

  Widget _page(FileItem item) {
    if (item.kind == FileKind.image) {
      return ImagePage(
        key: ValueKey(item.path),
        item: item,
        onZoomChanged: (z) {
          if (z != _zoomed) setState(() => _zoomed = z);
        },
        onTap: () => _setChrome(!_chrome),
      );
    }
    if (item.kind == FileKind.video) {
      return VideoPage(key: ValueKey(item.path), item: item, onControlsChanged: _setChrome);
    }
    if (item.kind == FileKind.audio) return AudioPage(key: ValueKey(item.path), item: item);
    if (item.kind == FileKind.pdf) return PdfPage(key: ValueKey(item.path), item: item);
    return TextPage(key: ValueKey(item.path), item: item);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = _current;
    final title = _items.length > 1 ? '${item.name}  (${_index + 1}/${_items.length})' : item.name;

    final body = item.kind == FileKind.image && _items.length > 1
        ? PageView.builder(
      controller: _pager,
      physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
      itemCount: _items.length,
      onPageChanged: (i) {
        setState(() {
          _index = i;
          _zoomed = false;
        });
        _precacheAround(i);
      },
      itemBuilder: (_, i) => _page(_items[i]),
    )
        : _page(item);

    final bar = AppBar(
      // Over a picture the bar is see-through, so the image is still visible.
      backgroundColor: _immersive ? Colors.black54 : null,
      foregroundColor: _immersive ? Colors.white : null,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      title: Text(title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
      actions: [
        IconButton(
          tooltip: 'Share',
          icon: const Icon(Icons.share_outlined),
          onPressed: () => SharePlus.instance.share(ShareParams(files: [XFile(item.path)])),
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'details':
                showFileDetails(context, item);
              case 'external':
                openExternally(context, item);
              case 'delete':
                _delete();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'details', child: Text('Details')),
            PopupMenuItem(value: 'external', child: Text('Open with another app')),
            PopupMenuItem(value: 'delete', child: Text('Move to trash')),
          ],
        ),
      ],
    );

    if (!_immersive) {
      return Scaffold(
        backgroundColor: scheme.surface,
        appBar: bar,
        body: SafeArea(top: false, child: body),
      );
    }

    // Images and videos fill the screen; the bar slides away with the controls.
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: body),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_chrome,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 200),
                offset: _chrome ? Offset.zero : const Offset(0, -1),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _chrome ? 1 : 0,
                  child: bar,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}