import 'package:flutter_test/flutter_test.dart';
import 'package:multi_tool_remote/services/steps_day_history.dart';

void main() {
  test('StepsDayHistory.dayKey formats ISO date', () {
    expect(
      StepsDayHistory.dayKey(DateTime(2026, 3, 21)),
      '2026-03-21',
    );
  });
}
