import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/file_item.dart';

class PdfPage extends StatefulWidget {
  const PdfPage({super.key, required this.item, this.onControlsChanged});

  final FileItem item;

  /// Called when the controls show or hide, so the viewer can hide its top bar
  /// and the system bars along with them (full-screen reading).
  final ValueChanged<bool>? onControlsChanged;

  @override
  State<PdfPage> createState() => _PdfPageState();
}

class _PdfPageState extends State<PdfPage> {
  final _controller = PdfViewerController();
  late final PdfTextSearcher _searcher = PdfTextSearcher(_controller)..addListener(_onSearch);
  final _query = TextEditingController();
  final _queryFocus = FocusNode();

  int _page = 1;
  int _count = 0;
  bool _searching = false;
  bool _night = false;
  Timer? _saveTimer;

  // The bottom bar hides itself, and a tap on the page shows or hides it.
  bool _controls = true;
  Timer? _hideTimer;
  Timer? _tapTimer;
  Offset? _downAt;
  DateTime _downTime = DateTime.now();
  int _pointers = 0;
  DateTime? _lastTapAt;
  Offset _lastTapPos = Offset.zero;
  bool _zoomedIn = false;

  String get _pageKey => 'pdf_page:${widget.item.path}';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _night = p.getBool('pdf_night') ?? false);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _tapTimer?.cancel();
    _saveTimer?.cancel();
    _savePage();
    _searcher.removeListener(_onSearch);
    _searcher.dispose();
    _query.dispose();
    _queryFocus.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_searching && _controls) _setControls(false);
    });
  }

  void _setControls(bool visible) {
    if (visible != _controls) {
      setState(() => _controls = visible);
      // While searching, the search bar owns the top of the screen.
      if (!_searching) widget.onControlsChanged?.call(visible);
    }
    if (visible) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  /// Handles a quick tap on the page. One tap shows or hides the controls; two
  /// quick taps zoom. The toggle waits a moment so a double tap doesn't also
  /// flash the controls.
  void _onPageTap(Offset position) {
    final now = DateTime.now();
    final last = _lastTapAt;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 300) &&
        (position - _lastTapPos).distance < 60) {
      _tapTimer?.cancel();
      _lastTapAt = null;
      _doubleTapZoom();
      return;
    }
    _lastTapAt = now;
    _lastTapPos = position;
    _tapTimer?.cancel();
    _tapTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _setControls(!_controls);
    });
  }

  /// Double tap: zoom in one step, and the next double tap zooms back out.
  void _doubleTapZoom() {
    if (_zoomedIn) {
      _controller.zoomDown();
    } else {
      _controller.zoomUp();
    }
    _zoomedIn = !_zoomedIn;
  }

  void _onSearch() {
    if (mounted) setState(() {});
  }

  /// Remembers the page so the PDF opens where you stopped.
  Future<void> _savePage() async {
    if (_count == 0) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_page <= 1) {
        await prefs.remove(_pageKey);
      } else {
        await prefs.setInt(_pageKey, _page);
      }
    } catch (_) {}
  }

  Future<void> _restorePage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_pageKey);
      if (saved != null && saved > 1 && saved <= _count && mounted) {
        await _controller.goToPage(pageNumber: saved, duration: Duration.zero);
      }
    } catch (_) {}
  }

  Future<void> _setNight(bool v) async {
    setState(() => _night = v);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('pdf_night', v);
    } catch (_) {}
  }

  void _toggleSearch() {
    setState(() => _searching = !_searching);
    if (_searching) {
      _hideTimer?.cancel();
      // Clear the top bar so the search bar has the space.
      widget.onControlsChanged?.call(false);
      _queryFocus.requestFocus();
    } else {
      _searcher.resetTextSearch();
      _query.clear();
      widget.onControlsChanged?.call(_controls);
      _scheduleHide();
    }
  }

  int _passwordTries = 0;

  Future<String?> _askPassword() async {
    if (!mounted) return null;
    // The reader asks again when the last password was wrong.
    final again = _passwordTries++ > 0;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PromptDialog(
        title: 'Password needed',
        hint: 'Password',
        confirmLabel: 'Open',
        obscure: true,
        error: again ? 'That password is not right. Try again' : null,
      ),
    );
  }

  Future<void> _jumpToPage() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _PromptDialog(
        title: 'Go to page',
        hint: '1 to $_count',
        confirmLabel: 'Go',
        number: true,
      ),
    );
    final n = int.tryParse(text?.trim() ?? '');
    if (n == null || _count == 0) return;
    await _controller.goToPage(pageNumber: n.clamp(1, _count));
  }

  Widget _tool(IconData icon, String tip, VoidCallback? onTap, {bool on = false}) {
    return IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      color: on ? Theme.of(context).colorScheme.primary : Colors.white,
      icon: Icon(icon, size: 22),
      onPressed: onTap,
    );
  }

  Widget _searchBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final matches = _searcher.matches.length;
    final current = _searcher.currentIndex;
    final label = _searcher.isSearching
        ? '…'
        : matches == 0
            ? (_query.text.isEmpty ? '' : '0')
            : '${(current ?? 0) + 1}/$matches';

    return Material(
      color: scheme.surfaceContainerHighest,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _query,
                focusNode: _queryFocus,
                textInputAction: TextInputAction.search,
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) _searcher.startTextSearch(v.trim());
                },
                decoration: InputDecoration(
                  hintText: 'Search in this PDF',
                  border: InputBorder.none,
                  filled: false,
                  suffixText: label,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Previous',
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: matches == 0 ? null : _searcher.goToPrevMatch,
            ),
            IconButton(
              tooltip: 'Next',
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: matches == 0 ? null : _searcher.goToNextMatch,
            ),
            IconButton(
              tooltip: 'Close search',
              icon: const Icon(Icons.close),
              onPressed: _toggleSearch,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;

    Widget viewer = PdfViewer.file(
      widget.item.path,
      controller: _controller,
      passwordProvider: _askPassword,
      params: PdfViewerParams(
        backgroundColor: scheme.surfaceContainerHighest,
        errorBannerBuilder: (context, error, stackTrace, documentRef) {
          final locked = error is PdfPasswordException;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(locked ? Icons.lock_outline : Icons.error_outline,
                      size: 56, color: scheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    locked ? 'This PDF needs a password' : "Couldn't open this PDF",
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    locked
                        ? 'Open it again and type the password to read it.'
                        : 'The file may be damaged.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Go back'),
                  ),
                ],
              ),
            ),
          );
        },
        pagePaintCallbacks: [_searcher.pageTextMatchPaintCallback],
        viewerOverlayBuilder: (context, size, handleLinkTap) => [
          PdfViewerScrollThumb(
            controller: _controller,
            orientation: ScrollbarOrientation.right,
            thumbSize: const Size(44, 26),
            thumbBuilder: (context, thumbSize, pageNumber, controller) => Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Center(
                child: Text(
                  '${pageNumber ?? ''}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
        onViewerReady: (document, controller) {
          if (!mounted) return;
          setState(() => _count = document.pages.length);
          _restorePage();
          _scheduleHide();
        },
        onPageChanged: (page) {
          if (page == null || !mounted) return;
          setState(() => _page = page);
          _saveTimer?.cancel();
          _saveTimer = Timer(const Duration(milliseconds: 600), _savePage);
        },
      ),
    );

    if (_night) {
      // Light text on a dark page, easier on the eyes in the dark.
      viewer = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          -1, 0, 0, 0, 255, //
          0, -1, 0, 0, 255,
          0, 0, -1, 0, 255,
          0, 0, 0, 1, 0,
        ]),
        child: viewer,
      );
    }

    // A Listener doesn't take part in gestures, so scrolling, pinching and
    // double-tap zoom keep working. It only spots a quick single tap.
    viewer = Listener(
      onPointerDown: (e) {
        _pointers++;
        _downAt = _pointers == 1 ? e.position : null;
        _downTime = DateTime.now();
      },
      onPointerUp: (e) {
        final start = _downAt;
        if (start != null &&
            (e.position - start).distance < 12 &&
            DateTime.now().difference(_downTime) < const Duration(milliseconds: 300)) {
          _onPageTap(e.position);
        }
        _downAt = null;
        _pointers = _pointers > 0 ? _pointers - 1 : 0;
      },
      onPointerCancel: (_) {
        _downAt = null;
        _pointers = 0;
      },
      child: viewer,
    );

    return Stack(
      children: [
        viewer,
        if (_searching)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(bottom: false, child: _searchBar(context)),
          ),
        if (_count > 0)
          Positioned(
            bottom: 16 + bottom,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_controls,
              child: AnimatedOpacity(
                opacity: _controls ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                // Using a button keeps the bar from hiding right away.
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) => _scheduleHide(),
                  child: Center(
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(24),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: _jumpToPage,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                        child: Text(
                          '$_page / $_count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    _tool(Icons.search, 'Search', _toggleSearch, on: _searching),
                    _tool(Icons.zoom_out, 'Zoom out', () => _controller.zoomDown()),
                    _tool(Icons.zoom_in, 'Zoom in', () => _controller.zoomUp()),
                    _tool(
                      Icons.fit_screen_outlined,
                      'Fit page',
                      () => _controller.goToPage(
                        pageNumber: _page,
                        anchor: PdfPageAnchor.all,
                      ),
                    ),
                    _tool(
                      _night ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                      'Reading mode',
                      () => _setNight(!_night),
                      on: _night,
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A one-line text prompt. It owns its controller, so the controller lives as
/// long as the dialog does, including while it fades out.
class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.hint,
    required this.confirmLabel,
    this.obscure = false,
    this.number = false,
    this.error,
  });

  final String? error;
  final String title;
  final String hint;
  final String confirmLabel;
  final bool obscure;
  final bool number;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: widget.obscure,
        keyboardType: widget.number ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(hintText: widget.hint, errorText: widget.error),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
