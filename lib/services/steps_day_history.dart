import 'package:shared_preferences/shared_preferences.dart';

/// Per-day step totals saved while tracking (pedometer), for week/month without Health.
class StepsDayHistory {
  StepsDayHistory._();

  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<void> saveSnapshot(DateTime day, int steps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('steps_snapshot_${dayKey(day)}', steps);
  }

  static Future<int?> readSnapshot(DateTime day) async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('steps_snapshot_${dayKey(day)}')) return null;
    return prefs.getInt('steps_snapshot_${dayKey(day)}');
  }
}
