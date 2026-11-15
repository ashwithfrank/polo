import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../models/file_item.dart';
import '../../widgets/open_external.dart';
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
  late final VideoPlayerController _controller;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = VideoPlayerController.file(File(widget.item.path));
    _controller.addListener(_onPlayerChanged);
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _controller.play();
      _scheduleHide();
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

  void _seekBy(int seconds) {
    final v = _controller.value;
    var target = v.position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (target > v.duration) target = v.duration;
    _controller.seekTo(target);
    if (_showControls) _scheduleHide();
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
                  Expanded(child: SeekBar(controller: _controller, color: Colors.white)),
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