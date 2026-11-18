import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../models/file_item.dart';
import '../../services/mp4_repair.dart';
import '../../widgets/open_external.dart';
import '../../widgets/polo_message.dart';
import '../../widgets/progress_dialog.dart';
import 'player_bits.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key, required this.item, required this.onControlsChanged});

  final FileItem item;

  /// Called when the controls show or hide, so the viewer can hide its top bar
  /// and the system bars along with them.
  final ValueChanged<bool> onControlsChanged;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> with WidgetsBindingObserver {
  late VideoPlayerController _controller;
  bool _ready = false;
  bool _failed = false;
  bool _showControls = true;
  bool _landscape = false;
  Timer? _hideTimer;

  // The "+10s" / "-10s" flash after a double tap.
  String? _seekHint;
  Alignment _seekHintAt = Alignment.center;
  Timer? _hintTimer;
  Offset _lastTap = Offset.zero;
  bool _warnedSeek = false;
  bool _repaired = false;

  static final _cacheDir = Directory('${Directory.systemTemp.path}/polo_video');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open(widget.item.path);
  }

  /// Starts playing [path]. After a repair it carries on from [resumeAt].
  void _open(String path, {Duration? resumeAt}) {
    final controller = VideoPlayerController.file(File(path));
    _controller = controller;
    controller.addListener(_onPlayerChanged);
    controller.initialize().then((_) async {
      if (!mounted) return;
      if (resumeAt != null) await controller.seekTo(resumeAt);
      if (!mounted) return;
      setState(() => _ready = true);
      controller.play();
      _scheduleHide();
      // A fragmented MP4 can't be skipped around even when it shows a length,
      // so check the file itself and fix it before anyone tries to seek.
      if (resumeAt == null) _checkOnOpen();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  void _onPlayerChanged() {
    // Bring the controls back when the video ends.
    if (hasFinished(_controller.value) && !_showControls && mounted) {
      _setControls(true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _controller.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _hintTimer?.cancel();
    _controller.removeListener(_onPlayerChanged);
    _controller.dispose();
    try {
      if (_cacheDir.existsSync()) _cacheDir.deleteSync(recursive: true);
    } catch (_) {}
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  void _setControls(bool visible) {
    if (visible == _showControls) return;
    setState(() => _showControls = visible);
    widget.onControlsChanged(visible);
    if (visible) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller.value.isPlaying) _setControls(false);
    });
  }

  void _togglePlay() {
    final v = _controller.value;
    if (hasFinished(v)) {
      _controller.seekTo(Duration.zero);
      _controller.play();
    } else if (v.isPlaying) {
      _controller.pause();
      _hideTimer?.cancel();
    } else {
      _controller.play();
      _scheduleHide();
    }
  }

  Future<void> _seekBy(int seconds) async {
    final v = _controller.value;
    // Without a known length the player can't jump at all (it would go back
    // to the start), so offer the fix instead.
    if (!hasKnownLength(v)) {
      _warnedSeek = false; // show the offer again if it was dismissed
      _seekFailed();
      return;
    }
    var target = v.position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (target > v.duration) target = v.duration;
    if (_showControls) _scheduleHide();
    if (!await seekChecked(_controller, target)) _seekFailed();
  }

  /// Runs once when a video opens. A fragmented MP4 is fixed right away, so
  /// skipping works from the first second. Anything else is left alone.
  Future<void> _checkOnOpen() async {
    var fixable = false;
    try {
      fixable = await Mp4Repair.needsRepair(widget.item.path);
    } catch (_) {}
    if (!mounted || _repaired) return;
    if (fixable) {
      _warnedSeek = true;
      await _repair();
    } else if (!hasKnownLength(_controller.value)) {
      _seekFailed();
    }
  }

  /// The player can't jump around in this video. If the file is a fragmented
  /// MP4, Polo fixes it by itself. Otherwise it suggests another app.
  Future<void> _seekFailed() async {
    if (!mounted || _warnedSeek || _repaired) return;
    _warnedSeek = true;

    var fixable = false;
    try {
      fixable = await Mp4Repair.needsRepair(widget.item.path);
    } catch (_) {}
    if (!mounted) return;

    if (fixable) {
      // Fix it automatically, no need to ask.
      await _repair();
    } else {
      showPoloMessage(
        context,
        "Skipping around doesn't work in Polo for this video",
        actionLabel: 'Open in another app',
        onAction: () => openExternally(context, widget.item),
      );
    }
  }

  /// Makes a seekable copy in the cache (the original is never changed) and
  /// carries on playing from the same place.
  Future<void> _repair() async {
    final position = _controller.value.position;
    _controller.pause();
    await _cacheDir.create(recursive: true);
    if (!mounted) return;
    final out = '${_cacheDir.path}/video.mp4';

    final String? error;
    try {
      error = await runWithProgress(
        context,
        'Making the video seekable…',
            () => Mp4Repair.makeSeekable(widget.item.path, out),
      );
    } catch (_) {
      if (mounted) showPoloMessage(context, "Couldn't fix this video");
      return;
    }
    if (!mounted) return;
    if (error != null) {
      showPoloMessage(context, error);
      return;
    }

    _repaired = true;
    setState(() => _ready = false);
    final old = _controller;
    await WidgetsBinding.instance.endOfFrame;
    old.removeListener(_onPlayerChanged);
    await old.dispose();
    if (!mounted) return;
    _open(out, resumeAt: position);
  }

  void _doubleTap(double width) {
    // Left third goes back, right third goes forward, the middle toggles play.
    final x = _lastTap.dx;
    if (x < width / 3) {
      _flashHint('-10s', Alignment.centerLeft);
      _seekBy(-10);
    } else if (x > width * 2 / 3) {
      _flashHint('+10s', Alignment.centerRight);
      _seekBy(10);
    } else {
      _togglePlay();
    }
  }

  void _flashHint(String text, Alignment at) {
    _hintTimer?.cancel();
    setState(() {
      _seekHint = text;
      _seekHintAt = at;
    });
    _hintTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _seekHint = null);
    });
  }

  void _rotate() {
    _landscape = !_landscape;
    SystemChrome.setPreferredOrientations(
      _landscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp],
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return PlaybackError(
        light: true,
        onOpenExternally: () => openExternally(context, widget.item),
      );
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _setControls(!_showControls),
        onDoubleTapDown: (d) => _lastTap = d.localPosition,
        onDoubleTap: () => _doubleTap(box.maxWidth),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
            ),
            // Buffering spinner.
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: _controller,
              builder: (_, v, _) => v.isBuffering
                  ? const Center(child: CircularProgressIndicator())
                  : const SizedBox.shrink(),
            ),
            if (_seekHint != null)
              Align(
                alignment: _seekHintAt,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _seekHint!,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            // Controls: fade in and out, and don't catch taps while hidden.
            IgnorePointer(
              ignoring: !_showControls,
              child: AnimatedOpacity(
                opacity: _showControls ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: _buildControls(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    return Container(
      color: Colors.black38,
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 36,
                  color: Colors.white,
                  icon: const Icon(Icons.replay_10),
                  onPressed: () => _seekBy(-10),
                ),
                const SizedBox(width: 16),
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: _controller,
                  builder: (_, v, _) => IconButton.filled(
                    iconSize: 44,
                    icon: Icon(
                      hasFinished(v)
                          ? Icons.replay
                          : v.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                    ),
                    onPressed: _togglePlay,
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  iconSize: 36,
                  color: Colors.white,
                  icon: const Icon(Icons.forward_10),
                  onPressed: () => _seekBy(10),
                ),
              ],
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 4, 4),
              child: Row(
                children: [
                  Expanded(child: SeekBar(controller: _controller, color: Colors.white, onSeekFailed: _seekFailed)),
                  SpeedMenu(controller: _controller, color: Colors.white),
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: _controller,
                    builder: (_, v, _) => IconButton(
                      color: v.isLooping ? Theme.of(context).colorScheme.primary : Colors.white,
                      tooltip: 'Repeat',
                      icon: Icon(v.isLooping ? Icons.repeat_on_outlined : Icons.repeat),
                      onPressed: () => _controller.setLooping(!v.isLooping),
                    ),
                  ),
                  IconButton(
                    color: Colors.white,
                    tooltip: 'Rotate',
                    icon: const Icon(Icons.screen_rotation_outlined),
                    onPressed: _rotate,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}