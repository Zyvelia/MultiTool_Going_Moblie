import 'dart:math';

import '../models/song.dart';

class PlaybackArrangement {
  const PlaybackArrangement(this.order, this.startIndex);

  final List<Song> order;

  /// Index in [order] of the song that should start playing.
  final int startIndex;
}

/// Orders a queue without the player's built-in shuffle mode.
///
/// just_audio's shuffle index does not match the audible item on iOS, and a
/// single-item source always reports index 0. The on-screen title follows
/// this list, and the player is given the same order with shuffle left off.
PlaybackArrangement arrangePlayback({
  required List<Song> songs,
  required int startIndex,
  bool shuffleAll = false,
  bool shuffleUpcoming = false,
  Random? random,
}) {
  if (songs.isEmpty) {
    return const PlaybackArrangement([], 0);
  }
  final start = startIndex.clamp(0, songs.length - 1);
  if (shuffleAll && songs.length > 1) {
    final copy = List<Song>.from(songs)..shuffle(random);
    return PlaybackArrangement(copy, 0);
  }
  if (shuffleUpcoming && songs.length > 1) {
    final rest = <Song>[
      for (var i = 0; i < songs.length; i++)
        if (i != start) songs[i],
    ]..shuffle(random);
    return PlaybackArrangement([songs[start], ...rest], 0);
  }
  return PlaybackArrangement(List<Song>.from(songs), start);
}

/// Where a player window should begin for [focusIndex].
///
/// Item 0 of the window is the song that should be heard. iOS often ignores
/// `initialIndex` and starts at the first queued item.
int playbackWindowStart(int focusIndex, int length) {
  if (length <= 0) return 0;
  return focusIndex.clamp(0, length - 1);
}
