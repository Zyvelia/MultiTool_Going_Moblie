import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_notification_service.dart';
import 'steps_widget_bridge.dart';

/// Goal hit notification (once per day) + widget refresh.
class StepsGoalCelebration {
  StepsGoalCelebration._();

  static const _goalNotifiedKey = 'steps_goal_notified_day';
  static const _notificationId = 88001;
  static const _payload = 'steps:goal';

  static Future<void> onStepsUpdated({
    required int todaySteps,
    required int dailyGoal,
  }) async {
    await StepsWidgetBridge.updateTodayCount(todaySteps);
    if (todaySteps < dailyGoal) return;

    final day = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_goalNotifiedKey) == day) return;
    await prefs.setString(_goalNotifiedKey, day);

    await LocalNotificationService.instance.show(
      id: _notificationId,
      title: 'Daily step goal reached',
      body:
          '${NumberFormat.decimalPattern().format(todaySteps)} steps — nice work.',
      channelId: 'z_steps',
      channelName: 'Steps',
      payload: _payload,
    );
  }
}
