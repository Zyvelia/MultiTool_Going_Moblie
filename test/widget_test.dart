import 'package:flutter_test/flutter_test.dart';
import 'package:multi_tool_remote/services/home_tabs.dart';

void main() {
  test('bottom-nav indices stay contiguous', () {
    expect(
      [
        HomeTabs.vault,
        HomeTabs.music,
        HomeTabs.notes,
        HomeTabs.reminders,
        HomeTabs.clock,
        HomeTabs.games,
        HomeTabs.yt,
        HomeTabs.send,
        HomeTabs.chat,
        HomeTabs.pc,
        HomeTabs.settings,
      ],
      List<int>.generate(11, (i) => i),
    );
  });
}
