import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'song_tile.dart';

/// Same visual shape as MiniPlayer, but for "Control PC" mode: there's
/// no local AudioPlayer to stream from, just whatever the desktop app
/// last reported over /api/now-playing. Position/duration/isPlaying are
/// pushed in from LibraryScreen's poll loop rather than read from a
/// player stream.
class PcMiniPlayer extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final max = duration > 0 ? duration : 1.0;
    final value = position.clamp(0.0, max);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.border)),
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
                  formatDuration(position.toInt()),
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
                      onChanged: onSeek,
                    ),
                  ),
                ),
                Text(
                  formatDuration(duration.toInt()),
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
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        artist,
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
                  color: hasPrev ? Colors.white : Colors.white24,
                  onPressed: hasPrev ? onPrev : null,
                ),
                IconButton(
                  iconSize: 40,
                  icon: Icon(isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled),
                  color: AppColors.accent,
                  onPressed: onPlayPause,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  color: hasNext ? Colors.white : Colors.white24,
                  onPressed: hasNext ? onNext : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
