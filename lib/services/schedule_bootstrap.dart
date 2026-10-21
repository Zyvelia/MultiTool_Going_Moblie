import 'alarm_service.dart';
import 'local_notification_service.dart';
import 'reminder_service.dart';

/// Re-arms all local schedules (alarms + reminders). Call on cold start,
/// resume from background, and after Android boot (via plugin receivers +
/// next app open).
class ScheduleBootstrap {
  static Future<void> rescheduleAll() async {
    await LocalNotificationService.instance.ensureTimezoneReady();
    await ReminderService.instance.rescheduleAll();
    await AlarmService.instance.rescheduleAll();
  }
}
