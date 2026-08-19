import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../theme/app_colors.dart';
import '../models/song.dart';
import 'song_tile.dart';

class MiniPlayer extends StatelessWidget {
  final AudioPlayer player;
  final Song song;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final bool hasPrev;
  final bool hasNext;

  const MiniPlayer({
    super.key,
    required this.player,
    required this.song,
    required this.onPrev,
    required this.onNext,
    required this.hasPrev,
    required this.hasNext,
  });

  @override
  Widget build(BuildContext context) {
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
            StreamBuilder<Duration>(
              stream: player.positionStream,
              builder: (context, snapshot) {
                final position = snapshot.data ?? Duration.zero;
                final duration = player.duration ?? Duration.zero;
                final max = duration.inMilliseconds > 0
                    ? duration.inMilliseconds.toDouble()
                    : 1.0;
                final value = position.inMilliseconds
                    .toDouble()
                    .clamp(0.0, max);
                return Row(
                  children: [
                    Text(
                      formatDuration(position.inSeconds),
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6),
                        ),
                        child: Slider(
                          value: value,
                          max: max,
                          activeColor: AppColors.accent,
                          inactiveColor: Colors.white24,
                          onChanged: (v) {
                            player.seek(Duration(milliseconds: v.toInt()));
                          },
                        ),
                      ),
                    ),
                    Text(
                      formatDuration(duration.inSeconds),
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11),
                    ),
                  ],
                );
              },
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  color: hasPrev ? Colors.white : Colors.white24,
                  onPressed: hasPrev ? onPrev : null,
                ),
                StreamBuilder<PlayerState>(
                  stream: player.playerStateStream,
                  builder: (context, snapshot) {
                    final playing = snapshot.data?.playing ?? false;
                    return IconButton(
                      iconSize: 40,
                      icon: Icon(
                          playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
                      color: AppColors.accent,
                      onPressed: () {
                        playing ? player.pause() : player.play();
                      },
                    );
                  },
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
