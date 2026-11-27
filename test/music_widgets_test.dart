import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multi_tool_remote/widgets/pc_mini_player.dart';
import 'package:multi_tool_remote/widgets/song_tile.dart';

void main() {
  test('music timer starts at zero', () {
    expect(formatDuration(0), '0:00');
    expect(formatDuration(65), '1:05');
  });

  testWidgets('PC seek sends only the final drag value', (tester) async {
    final seeks = <double>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PcMiniPlayer(
      title: 'Track', artist: 'Artist', isPlaying: true,
      position: 10, duration: 100, hasPrev: true, hasNext: true,
      onPlayPause: () {}, onPrev: () {}, onNext: () {}, onSeek: seeks.add,
    ))));
    final slider = find.byType(Slider);
    final rect = tester.getRect(slider);
    final gesture = await tester.startGesture(rect.center);
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(seeks, isEmpty);
    await gesture.up();
    await tester.pump();
    expect(seeks, hasLength(1));
  });
}
