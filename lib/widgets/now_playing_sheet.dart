import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';
import '../services/phone_playback.dart';
import '../theme/app_colors.dart';
import 'song_tile.dart';

/// Full-screen-style now playing panel (tap the mini bar to open).
class NowPlayingSheet extends StatefulWidget {
  const NowPlayingSheet({
    super.key,
    required this.player,
    required this.song,
    required this.onPrev,
    required this.onNext,
    required this.hasPrev,
    required this.hasNext,
    required this.shuffleOn,
    required this.loopMode,
    required this.onToggleShuffle,
    required this.onToggleRepeat,
    this.onPlayAll,
    this.onShuffleAll,
  });

  final PhonePlayback player;
  final Song song;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final bool hasPrev;
  final bool hasNext;
  final bool shuffleOn;
  final LoopMode loopMode;
  final VoidCallback onToggleShuffle;
  final VoidCallback onToggleRepeat;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShuffleAll;

  static Future<void> show(
    BuildContext context, {
    required PhonePlayback player,
    required Song song,
    required VoidCallback onPrev,
    required VoidCallback onNext,
    required bool hasPrev,
    required bool hasNext,
    required bool shuffleOn,
    required LoopMode loopMode,
    required VoidCallback onToggleShuffle,
    required VoidCallback onToggleRepeat,
    VoidCallback? onPlayAll,
    VoidCallback? onShuffleAll,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => NowPlayingSheet(
        player: player,
        song: song,
        onPrev: onPrev,
        onNext: onNext,
        hasPrev: hasPrev,
        hasNext: hasNext,
        shuffleOn: shuffleOn,
        loopMode: loopMode,
        onToggleShuffle: onToggleShuffle,
        onToggleRepeat: onToggleRepeat,
        onPlayAll: onPlayAll,
        onShuffleAll: onShuffleAll,
      ),
    );
  }

  @override
  State<NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<NowPlayingSheet> {
  double _volume = 1.0;

  @override
  void initState() {
    super.initState();
    _volume = widget.player.volume;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.94,
      minChildSize: 0.5,
      maxChildSize: 0.98,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(20, 8, 20, bottom + 16),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  if (widget.onPlayAll != null)
                    TextButton(
                      onPressed: widget.onPlayAll,
                      child: const Text('Play all'),
                    ),
                  if (widget.onShuffleAll != null)
                    TextButton(
                      onPressed: widget.onShuffleAll,
                      child: const Text('Shuffle all'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.wine, AppColors.accentMuted],
                    ),
                  ),
                  child: const Icon(
                    Icons.album,
                    size: 96,
                    color: AppColors.accentGlow,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                widget.song.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.song.artist,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 16),
              ),
              if (widget.song.album.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  widget.song.album,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ],
              const SizedBox(height: 24),
              StreamBuilder<Duration>(
                stream: widget.player.positionStream,
                builder: (context, snapshot) {
                  final position = snapshot.data ?? Duration.zero;
                  final duration = widget.player.duration ?? Duration.zero;
                  final maxMs = duration.inMilliseconds > 0
                      ? duration.inMilliseconds.toDouble()
                      : 1.0;
                  final value =
                      position.inMilliseconds.toDouble().clamp(0.0, maxMs);
                  return Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7,
                          ),
                        ),
                        child: Slider(
                          value: value,
                          max: maxMs,
                          activeColor: AppColors.accent,
                          inactiveColor: Colors.white24,
                          onChanged: (v) {
                            widget.player
                                .seek(Duration(milliseconds: v.round()));
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              formatDuration(position.inSeconds),
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              formatDuration(duration.inSeconds),
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              StreamBuilder<bool>(
                stream: widget.player.shuffleModeEnabledStream,
                builder: (context, shuffleSnap) {
                  final shuffleOn = shuffleSnap.data ?? widget.shuffleOn;
                  return StreamBuilder<LoopMode>(
                    stream: widget.player.loopModeStream,
                    builder: (context, loopSnap) {
                      final loop = loopSnap.data ?? widget.loopMode;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            iconSize: 28,
                            icon: Icon(
                              Icons.shuffle,
                              color: shuffleOn
                                  ? AppColors.accent
                                  : Colors.white38,
                            ),
                            onPressed: widget.onToggleShuffle,
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            iconSize: 36,
                            icon: const Icon(Icons.skip_previous),
                            color:
                                widget.hasPrev ? Colors.white : Colors.white24,
                            onPressed: widget.hasPrev ? widget.onPrev : null,
                          ),
                          const SizedBox(width: 4),
                          StreamBuilder<PlayerState>(
                            stream: widget.player.playerStateStream,
                            builder: (context, snapshot) {
                              final playing =
                                  snapshot.data?.playing ?? false;
                              return IconButton(
                                iconSize: 64,
                                icon: Icon(
                                  playing
                                      ? Icons.pause_circle_filled
                                      : Icons.play_circle_filled,
                                ),
                                color: AppColors.accent,
                                onPressed: () {
                                  playing
                                      ? widget.player.pause()
                                      : widget.player.play();
                                },
                              );
                            },
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            iconSize: 36,
                            icon: const Icon(Icons.skip_next),
                            color:
                                widget.hasNext ? Colors.white : Colors.white24,
                            onPressed: widget.hasNext ? widget.onNext : null,
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            iconSize: 28,
                            icon: Icon(
                              loop == LoopMode.one
                                  ? Icons.repeat_one
                                  : Icons.repeat,
                              color: loop == LoopMode.off
                                  ? Colors.white38
                                  : AppColors.accent,
                            ),
                            onPressed: widget.onToggleRepeat,
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Icon(
                    _volume < 0.05 ? Icons.volume_off : Icons.volume_up,
                    color: Colors.white54,
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                      ),
                      child: Slider(
                        value: _volume.clamp(0.0, 1.0),
                        onChanged: (v) {
                          setState(() => _volume = v);
                          widget.player.setVolume(v);
                        },
                        activeColor: AppColors.accentGlow,
                        inactiveColor: Colors.white24,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
