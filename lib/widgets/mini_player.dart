import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../theme/app_colors.dart';
import '../models/song.dart';

/// Compact bar — tap anywhere (except play) to open [NowPlayingSheet].
class MiniPlayer extends StatelessWidget {
  final AudioPlayer player;
  final Song song;
  final VoidCallback onOpenExpanded;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final bool hasPrev;
  final bool hasNext;

  const MiniPlayer({
    super.key,
    required this.player,
    required this.song,
    required this.onOpenExpanded,
    required this.onPrev,
    required this.onNext,
    required this.hasPrev,
    required this.hasNext,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onOpenExpanded,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            gradient: const LinearGradient(
                              colors: [AppColors.wine, AppColors.accentMuted],
                            ),
                          ),
                          child: const Icon(
                            Icons.music_note,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.keyboard_arrow_up,
                          color: Colors.white38,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.skip_previous, size: 26),
                color: hasPrev ? Colors.white70 : Colors.white24,
                onPressed: hasPrev ? onPrev : null,
              ),
              StreamBuilder<PlayerState>(
                stream: player.playerStateStream,
                builder: (context, snapshot) {
                  final playing = snapshot.data?.playing ?? false;
                  return IconButton(
                    iconSize: 42,
                    icon: Icon(
                      playing
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                    ),
                    color: AppColors.accent,
                    onPressed: () {
                      playing ? player.pause() : player.play();
                    },
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.skip_next, size: 26),
                color: hasNext ? Colors.white70 : Colors.white24,
                onPressed: hasNext ? onNext : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
