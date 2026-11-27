import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'song_tile.dart';

/// Same visual shape as MiniPlayer, but for "Control PC" mode: there's
/// no local AudioPlayer to stream from, just whatever the desktop app
/// last reported over /api/now-playing. Position/duration/isPlaying are
/// pushed in from LibraryScreen's poll loop rather than read from a
/// player stream.
class PcMiniPlayer extends StatefulWidget {
  final String title;
  final String artist;
  final bool isPlaying;
  final double position; // seconds
  final double duration; // seconds
  final bool hasPrev;
  final bool hasNext;
  final VoidCallback onPlayPause;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<double> onSeek;

  const PcMiniPlayer({
    super.key,
    required this.title,
    required this.artist,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.hasPrev,
    required this.hasNext,
    required this.onPlayPause,
    required this.onPrev,
    required this.onNext,
    required this.onSeek,
  });

  @override
  State<PcMiniPlayer> createState() => _PcMiniPlayerState();
}

class _PcMiniPlayerState extends State<PcMiniPlayer> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final duration = widget.duration;
    final position = widget.position;
    final max = duration.isFinite && duration > 0 ? duration : 1.0;
    final value = (_drag ?? (position.isFinite ? position : 0.0)).clamp(0.0, max);

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 3, 10, 6),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.wine, AppColors.surface]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.desktop_windows,
                    size: 12, color: AppColors.accent),
                const SizedBox(width: 4),
                const Text('Controlling PC',
                    style: TextStyle(color: AppColors.accent, fontSize: 10)),
              ],
            ),
            Row(
              children: [
                Text(
                  formatDuration(value.toInt()),
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      value: value,
                      max: max,
                      activeColor: AppColors.accent,
                      inactiveColor: Colors.white24,
                      onChanged: duration > 0 ? (v) => setState(() => _drag = v) : null,
                      onChangeEnd: (v) {
                        setState(() => _drag = null);
                        widget.onSeek(v);
                      },
                    ),
                  ),
                ),
                Text(
                  formatDuration(duration.isFinite ? duration.toInt() : 0),
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        widget.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  color: widget.hasPrev ? Colors.white : Colors.white24,
                  onPressed: widget.hasPrev ? widget.onPrev : null,
                ),
                IconButton(
                  iconSize: 40,
                  icon: Icon(widget.isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled),
                  color: AppColors.accent,
                  onPressed: widget.onPlayPause,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  color: widget.hasNext ? Colors.white : Colors.white24,
                  onPressed: widget.hasNext ? widget.onNext : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
