import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../models/file_item.dart';
import '../../widgets/open_external.dart';
import 'player_bits.dart';

class AudioPage extends StatefulWidget {
  const AudioPage({super.key, required this.item});

  final FileItem item;

  @override
  State<AudioPage> createState() => _AudioPageState();
}

class _AudioPageState extends State<AudioPage> with WidgetsBindingObserver {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = VideoPlayerController.file(File(widget.item.path));
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _controller.play();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _controller.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  void _seekBy(int seconds) {
    final v = _controller.value;
    var target = v.position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (target > v.duration) target = v.duration;
    _controller.seekTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_failed) {
      return PlaybackError(onOpenExternally: () => openExternally(context, widget.item));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(40),
            ),
            child: Icon(Icons.music_note_rounded, size: 96, color: scheme.primary),
          ),
          const SizedBox(height: 32),
          Text(
            widget.item.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            widget.item.sizeLabel,
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 24),
          if (!_ready)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )
          else ...[
            SeekBar(controller: _controller),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 36,
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
                    onPressed: () {
                      if (hasFinished(v)) {
                        _controller.seekTo(Duration.zero);
                        _controller.play();
                      } else {
                        v.isPlaying ? _controller.pause() : _controller.play();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  iconSize: 36,
                  icon: const Icon(Icons.forward_10),
                  onPressed: () => _seekBy(10),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SpeedMenu(controller: _controller),
                const SizedBox(width: 8),
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: _controller,
                  builder: (_, v, _) => IconButton(
                    tooltip: 'Repeat',
                    color: v.isLooping ? scheme.primary : null,
                    icon: Icon(v.isLooping ? Icons.repeat_on_outlined : Icons.repeat),
                    onPressed: () => _controller.setLooping(!v.isLooping),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}