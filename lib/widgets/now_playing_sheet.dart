import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';
import '../services/phone_playback.dart';
import '../theme/app_colors.dart';
import 'song_tile.dart';

/// What the full-screen player should show. Updated as the queue moves so the
/// title stays on the song that is actually playing.
class NowPlayingSnapshot {
  const NowPlayingSnapshot({
    required this.song,
    required this.hasPrev,
    required this.hasNext,
    required this.shuffleOn,
    required this.loopMode,
  });

  final Song song;
  final bool hasPrev;
  final bool hasNext;
  final bool shuffleOn;
  final LoopMode loopMode;
}

/// Full-screen-style now playing panel (tap the mini bar to open).
class NowPlayingSheet extends StatefulWidget {
  const NowPlayingSheet({
    super.key,
    required this.player,
    required this.snapshot,
    required this.onPrev,
    required this.onNext,
    required this.onToggleShuffle,
    required this.onToggleRepeat,
    this.onPlayAll,
    this.onShuffleAll,
  });

  final PhonePlayback player;
  final ValueListenable<NowPlayingSnapshot?> snapshot;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToggleShuffle;
  final VoidCallback onToggleRepeat;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShuffleAll;

  static Future<void> show(
    BuildContext context, {
    required PhonePlayback player,
    required ValueListenable<NowPlayingSnapshot?> snapshot,
    required VoidCallback onPrev,
    required VoidCallback onNext,
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
        snapshot: snapshot,
        onPrev: onPrev,
        onNext: onNext,
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
  NowPlayingSnapshot? _snap;

  @override
  void initState() {
    super.initState();
    _volume = widget.player.volume;
    _snap = widget.snapshot.value;
    widget.snapshot.addListener(_onSnapshot);
  }

  @override
  void didUpdateWidget(NowPlayingSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot != widget.snapshot) {
      oldWidget.snapshot.removeListener(_onSnapshot);
      widget.snapshot.addListener(_onSnapshot);
      _snap = widget.snapshot.value;
    }
  }

  void _onSnapshot() {
    if (!mounted) return;
    setState(() => _snap = widget.snapshot.value);
  }

  @override
  void dispose() {
    widget.snapshot.removeListener(_onSnapshot);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    if (snap == null) return const SizedBox.shrink();
    final song = snap.song;
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
                song.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                song.artist,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 16),
              ),
              if (song.album.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  song.album,
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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 28,
                    icon: Icon(
                      Icons.shuffle,
                      color: snap.shuffleOn
                          ? AppColors.accent
                          : Colors.white38,
                    ),
                    onPressed: widget.onToggleShuffle,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    iconSize: 36,
                    icon: const Icon(Icons.skip_previous),
                    color: snap.hasPrev ? Colors.white : Colors.white24,
                    onPressed: snap.hasPrev ? widget.onPrev : null,
                  ),
                  const SizedBox(width: 4),
                  StreamBuilder<PlayerState>(
                    stream: widget.player.playerStateStream,
                    builder: (context, snapshot) {
                      final playing = snapshot.data?.playing ?? false;
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
                    color: snap.hasNext ? Colors.white : Colors.white24,
                    onPressed: snap.hasNext ? widget.onNext : null,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    iconSize: 28,
                    icon: Icon(
                      snap.loopMode == LoopMode.one
                          ? Icons.repeat_one
                          : Icons.repeat,
                      color: snap.loopMode == LoopMode.off
                          ? Colors.white38
                          : AppColors.accent,
                    ),
                    onPressed: widget.onToggleRepeat,
                  ),
                ],
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
