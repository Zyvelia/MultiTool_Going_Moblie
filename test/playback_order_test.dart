import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:multi_tool_remote/models/song.dart';
import 'package:multi_tool_remote/services/playback_order.dart';

Song _song(int id, String title) {
  return Song(id: id, title: title, artist: 'Artist $id', album: '', duration: 1);
}

void main() {
  final songs = [
    _song(1, 'One'),
    _song(2, 'Two'),
    _song(3, 'Three'),
    _song(4, 'Four'),
  ];

  test('normal play keeps library order and the tapped index', () {
    final arranged = arrangePlayback(songs: songs, startIndex: 2);
    expect(arranged.startIndex, 2);
    expect(arranged.order.map((s) => s.id), [1, 2, 3, 4]);
  });

  test('shuffle keeps the tapped song first and every song once', () {
    final arranged = arrangePlayback(
      songs: songs,
      startIndex: 2,
      shuffleUpcoming: true,
      random: Random(1),
    );
    expect(arranged.startIndex, 0);
    expect(arranged.order.first.id, 3);
    expect(arranged.order.map((s) => s.id).toSet(), {1, 2, 3, 4});
    expect(arranged.order.length, 4);
  });

  test('shuffle all starts at the first shuffled song', () {
    final arranged = arrangePlayback(
      songs: songs,
      startIndex: 0,
      shuffleAll: true,
      random: Random(2),
    );
    expect(arranged.startIndex, 0);
    expect(arranged.order.map((s) => s.id).toSet(), {1, 2, 3, 4});
    expect(arranged.order.length, 4);
    expect(arranged.order[arranged.startIndex].title, isNotEmpty);
  });

  test('player window starts on the song that should be heard', () {
    expect(playbackWindowStart(10, 40), 10);
    expect(playbackWindowStart(0, 40), 0);
    expect(playbackWindowStart(-1, 40), 0);
    expect(playbackWindowStart(50, 40), 39);
  });
}
