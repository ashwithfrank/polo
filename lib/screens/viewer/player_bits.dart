import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// True once playback has reached the end.
bool hasFinished(VideoPlayerValue v) =>
    v.isInitialized &&
        !v.isPlaying &&
        v.duration >= const Duration(seconds: 1) &&
        v.position >= v.duration - const Duration(milliseconds: 250);

/// Whether the player knows how long the video is. Some files report no length
/// at all and the player then says "1 millisecond" instead of 0, so anything
/// under a second counts as unknown.
bool hasKnownLength(VideoPlayerValue v) => v.duration >= const Duration(seconds: 1);

/// Jumps to [target], then checks that the player really got there. Some
/// files (for example MKV videos with no seek index) can't be skipped around
/// in by the player, and it silently restarts from the beginning instead.
/// Returns false when that happened.
Future<bool> seekChecked(VideoPlayerController controller, Duration target) async {
  await controller.seekTo(target);
  // Too close to the start to tell a failed jump from a real one.
  if (target < const Duration(seconds: 5)) {
    return true;
  }
  await Future<void>.delayed(const Duration(milliseconds: 900));
  final position = controller.value.position;
  final ok = position >= target - const Duration(seconds: 3);
  return ok;
}

/// Seek bar with elapsed and total time. While you drag, the thumb follows
/// your finger; the video only jumps when you let go.
class SeekBar extends StatefulWidget {
  const SeekBar({super.key, required this.controller, this.color, this.onSeekFailed});

  final VideoPlayerController controller;
  final Color? color;

  /// Called when a jump didn't work (see [seekChecked]).
  final VoidCallback? onSeekFailed;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final fg = widget.color ?? Theme.of(context).colorScheme.onSurface;
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final total = value.duration.inMilliseconds;
        // Some files don't say how long they are. The time still counts up,
        // but the bar can't move and the length shows as "--:--".
        final known = hasKnownLength(value);
        final max = (known ? total : 1).toDouble();
        final raw = _drag ?? value.position.inMilliseconds.toDouble();
        final pos = known ? raw.clamp(0.0, max) : 0.0;
        final shown = Duration(milliseconds: raw.round());
        return Row(
          children: [
            Text(formatDuration(shown), style: TextStyle(color: fg, fontSize: 12)),
            Expanded(
              child: Slider(
                value: pos,
                max: max,
                onChanged: known ? (v) => setState(() => _drag = v) : null,
                onChangeEnd: (v) {
                  seekChecked(widget.controller, Duration(milliseconds: v.round())).then((ok) {
                    if (!ok) widget.onSeekFailed?.call();
                  });
                  setState(() => _drag = null);
                },
              ),
            ),
            Text(known ? formatDuration(value.duration) : '--:--', style: TextStyle(color: fg, fontSize: 12)),
          ],
        );
      },
    );
  }
}

/// Playback speed picker.
class SpeedMenu extends StatelessWidget {
  const SpeedMenu({super.key, required this.controller, this.color});

  final VideoPlayerController controller;
  final Color? color;

  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  static String _label(double s) => s == s.roundToDouble() ? '${s.round()}x' : '${s}x';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) => PopupMenuButton<double>(
        tooltip: 'Speed',
        initialValue: value.playbackSpeed,
        onSelected: controller.setPlaybackSpeed,
        itemBuilder: (_) => [
          for (final s in _speeds)
            CheckedPopupMenuItem(
              value: s,
              checked: value.playbackSpeed == s,
              child: Text(_label(s)),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Text(
            _label(value.playbackSpeed),
            style: TextStyle(
              color: color ?? Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when a video or audio file can't be played.
class PlaybackError extends StatelessWidget {
  const PlaybackError({super.key, required this.onOpenExternally, this.light = false});

  final VoidCallback onOpenExternally;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final color = light ? Colors.white : Theme.of(context).colorScheme.onSurface;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: color.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text(
              "This phone can't play this file in Polo",
              textAlign: TextAlign.center,
              style: TextStyle(color: color),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onOpenExternally,
              child: const Text('Open with another app'),
            ),
          ],
        ),
      ),
    );
  }
}