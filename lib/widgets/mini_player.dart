import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../services/phone_playback.dart';
import '../theme/app_colors.dart';
import '../models/song.dart';

/// Compact bar — tap anywhere (except play) to open [NowPlayingSheet].
class MiniPlayer extends StatelessWidget {
  final PhonePlayback player;
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
      color: AppColors.bg,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 3, 10, 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.wine, AppColors.surface]),
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
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
                          width: 38,
                          height: 38,
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
                        const SizedBox(width: 8),
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
 
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Previous track',
                icon: const Icon(Icons.skip_previous, size: 23),
                color: hasPrev ? Colors.white70 : Colors.white24,
                onPressed: hasPrev ? onPrev : null,
              ),
              StreamBuilder<PlayerState>(
                stream: player.playerStateStream,
                builder: (context, snapshot) {
                  final playing = (snapshot.data?.playing ?? false) && snapshot.data?.processingState != ProcessingState.completed;
                  return IconButton(
                    tooltip: playing ? 'Pause' : 'Play',
                    iconSize: 36,
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
                tooltip: 'Next track',
                icon: const Icon(Icons.skip_next, size: 23),
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
