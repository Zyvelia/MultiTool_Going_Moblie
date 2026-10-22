import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pedometer_service.dart';
import 'steps_day_history.dart';
import 'steps_goal_celebration.dart';
import 'steps_health_capabilities.dart';

class DaySteps {
  const DaySteps(this.date, this.steps);

  final DateTime date;

  /// `null` = no data (show blank). `0` = known zero steps.
  final int? steps;
}

/// Steps tab: **pedometer first** (motion sensor). Health optional for history.
class StepsHealthService extends ChangeNotifier {
  StepsHealthService._();

  static final StepsHealthService instance = StepsHealthService._();

  final Health _health = Health();
  final PedometerService _pedometer = PedometerService.instance;

  static const _goalPrefsKey = 'steps_daily_goal';
  static const _healthSyncKey = 'steps_sync_health';

  bool configured = false;

  bool get healthSyncAvailable => StepsHealthCapabilities.healthSyncAvailable;
  bool healthAuthorized = false;
  bool syncWithHealth = false;
  bool loading = false;
  bool healthConnectAvailable = true;
  String? healthErrorMessage;
  int todaySteps = 0;
  List<DaySteps> lastSevenDays = const [];
  List<DaySteps> lastThirtyDays = const [];

  List<DaySteps> calendarWeek = const [];
  List<DaySteps> calendarMonth = const [];
  List<DaySteps?> calendarMonthGrid = const [];
  int dailyGoal = 10000;
  DateTime? lastRefresh;

  int get streakDays => _streakDays;
  int get sevenDayAverage => _sevenDayAverage;
  int get bestDayInWeek => _bestDayInWeek;

  /// One-shot flags for in-app celebration overlays (cleared by UI).
  bool goalCelebrationPending = false;
  bool streakCelebrationPending = false;

  int _streakDays = 0;
  int _sevenDayAverage = 0;
  int _bestDayInWeek = 0;
  int _prevStreakForBurst = 0;
  bool _wasBelowGoal = true;

  Timer? _calendarDebounce;
  bool _calendarRebuildRunning = false;
  bool _calendarRebuildQueued = false;

  double get todayDistanceKm => todaySteps * 0.000762;

  bool get isSupported => _pedometer.isSupported;

  bool get allowTracking => _pedometer.allowTracking;

  bool get pedometerListening => _pedometer.listening;

  bool get activityPermissionDenied => _pedometer.activityPermissionDenied;

  String get pedestrianStatus => _pedometer.pedestrianStatus;

  String? get errorMessage => _pedometer.errorMessage ?? healthErrorMessage;

  void clearCelebrations() {
    goalCelebrationPending = false;
    streakCelebrationPending = false;
  }

  Future<void> _ensureConfigured() async {
    final prefs = await SharedPreferences.getInstance();
    dailyGoal = prefs.getInt(_goalPrefsKey) ?? 10000;
    syncWithHealth = prefs.getBool(_healthSyncKey) ?? false;
    if (!healthSyncAvailable) {
      if (syncWithHealth) {
        syncWithHealth = false;
        await prefs.setBool(_healthSyncKey, false);
      }
      healthErrorMessage = null;
    }
    await _pedometer.loadPrefs();
    _wasBelowGoal = todaySteps < dailyGoal;
    await _ensureHealthPlugin();
  }

  Future<void> _ensureHealthPlugin() async {
    if (!healthSyncAvailable || !syncWithHealth) return;
    if (configured) return;
    await _health.configure();
    configured = true;
  }

  Future<void> setAllowTracking(bool value) async {
    await _pedometer.setAllowTracking(value);
    _pullTodayFromPedometer();
    notifyListeners();
  }

  Future<void> setSyncWithHealth(bool value) async {
    if (!healthSyncAvailable) {
      healthErrorMessage = StepsHealthCapabilities.iosMotionOnlyMessage;
      syncWithHealth = false;
      notifyListeners();
      return;
    }
    syncWithHealth = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_healthSyncKey, value);
    if (value) {
      await _ensureHealthPlugin();
      await refresh(requestHealthPermission: true);
    } else {
      healthErrorMessage = null;
    }
    notifyListeners();
  }

  Future<void> setDailyGoal(int goal) async {
    dailyGoal = goal.clamp(1000, 100_000);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_goalPrefsKey, dailyGoal);
    await _rebuildCalendarFromCache();
    _recomputeStatsFromCalendar();
    notifyListeners();
  }

  Future<void> installHealthConnect() => _health.installHealthConnect();

  void _pullTodayFromPedometer() {
    todaySteps = _pedometer.todaySteps;
  }

  void attachPedometer() {
    _pedometer.addListener(_onPedometer);
  }

  void detachPedometer() {
    _pedometer.removeListener(_onPedometer);
    _calendarDebounce?.cancel();
  }

  void _onPedometer() {
    _pullTodayFromPedometer();
    final hitGoal = todaySteps >= dailyGoal && _wasBelowGoal;
    if (hitGoal) goalCelebrationPending = true;
    _wasBelowGoal = todaySteps < dailyGoal;
    unawaited(_persistTodaySnapshot());
    if (hitGoal) {
      unawaited(
        StepsGoalCelebration.onStepsUpdated(
          todaySteps: todaySteps,
          dailyGoal: dailyGoal,
        ),
      );
    }
    _scheduleCalendarRebuild();
    notifyListeners();
  }

  void _scheduleCalendarRebuild() {
    _calendarDebounce?.cancel();
    _calendarDebounce = Timer(const Duration(milliseconds: 750), () {
      unawaited(_runCalendarRebuild());
    });
  }

  Future<void> _runCalendarRebuild() async {
    if (_calendarRebuildRunning) {
      _calendarRebuildQueued = true;
      return;
    }
    _calendarRebuildRunning = true;
    do {
      _calendarRebuildQueued = false;
      await _rebuildCalendarFromCache();
      await _computeStreakDays();
      _recomputeStatsFromCalendar();
      await _maybeStreakCelebration();
    } while (_calendarRebuildQueued);
    _calendarRebuildRunning = false;
    notifyListeners();
  }

  Future<void> _persistTodaySnapshot() async {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    await StepsDayHistory.saveSnapshot(day, todaySteps);
  }

  Future<void> _maybeStreakCelebration() async {
    if (_streakDays > _prevStreakForBurst && _streakDays > 0) {
      streakCelebrationPending = true;
    }
    _prevStreakForBurst = _streakDays;
  }

  Future<void> startTracking() async {
    await _ensureConfigured();
    attachPedometer();
    await _pedometer.start();
    _pullTodayFromPedometer();
    _wasBelowGoal = todaySteps < dailyGoal;
    await _runCalendarRebuild();
    notifyListeners();
  }

  Future<void> refresh({bool requestHealthPermission = false}) async {
    if (!isSupported) {
      healthErrorMessage = 'Steps need iOS or Android.';
      notifyListeners();
      return;
    }

    await _ensureConfigured();
    await _pedometer.start();
    _pullTodayFromPedometer();

    await _runCalendarRebuild();

    if (!healthSyncAvailable || !syncWithHealth) {
      healthErrorMessage = null;
      lastRefresh = DateTime.now();
      notifyListeners();
      return;
    }

    await _ensureHealthPlugin();
    loading = true;
    healthErrorMessage = null;
    notifyListeners();

    try {
      if (Platform.isAndroid) {
        healthConnectAvailable = await _health.isHealthConnectAvailable();
        if (!healthConnectAvailable) {
          loading = false;
          notifyListeners();
          return;
        }
      }

      const types = [HealthDataType.STEPS];
      const permissions = [HealthDataAccess.READ];

      var permitted =
          await _health.hasPermissions(types, permissions: permissions);
      if (permitted != true && requestHealthPermission) {
        permitted =
            await _health.requestAuthorization(types, permissions: permissions);
      }
      healthAuthorized = permitted == true;

      if (!healthAuthorized) {
        healthErrorMessage = Platform.isIOS
            ? 'Apple Health needs a build signed with HealthKit on your Apple ID. '
                'Step counting still works via motion sensor without Health.'
            : 'Allow Health Connect for full history. Pedometer works without it.';
        loading = false;
        notifyListeners();
        return;
      }

      if (Platform.isAndroid && await _health.isHealthDataHistoryAvailable()) {
        if (!await _health.isHealthDataHistoryAuthorized()) {
          await _health.requestHealthDataHistoryAuthorization();
        }
      }

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      final healthToday =
          await _health.getTotalStepsInInterval(todayStart, now) ?? 0;
      todaySteps =
          healthToday > _pedometer.todaySteps ? healthToday : _pedometer.todaySteps;

      final week = <DaySteps>[];
      for (var offset = 6; offset >= 0; offset--) {
        week.add(await _daySteps(todayStart, offset, now));
      }
      lastSevenDays = week;

      final month = <DaySteps>[];
      for (var offset = 29; offset >= 0; offset--) {
        month.add(await _daySteps(todayStart, offset, now));
      }
      lastThirtyDays = month;

      await _mergeHealthIntoCalendar(now);
      await _computeStreakDays();
      _recomputeStatsFromCalendar();
      lastRefresh = DateTime.now();
    } catch (e) {
      healthErrorMessage = e.toString();
    }

    loading = false;
    notifyListeners();
  }

  Future<DaySteps> _daySteps(
    DateTime todayStart,
    int daysAgo,
    DateTime now,
  ) async {
    final dayStart = todayStart.subtract(Duration(days: daysAgo));
    final dayEnd = daysAgo == 0
        ? now
        : dayStart
            .add(const Duration(days: 1))
            .subtract(const Duration(milliseconds: 1));
    final steps = await _health.getTotalStepsInInterval(dayStart, dayEnd);
    return DaySteps(dayStart, steps);
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _weekStartMonday(DateTime day) =>
      day.subtract(Duration(days: day.weekday - DateTime.monday));

  Future<void> _rebuildCalendarFromCache() async {
    final now = DateTime.now();
    final today = _dateOnly(now);

    final weekStart = _weekStartMonday(today);
    final week = <DaySteps>[];
    for (var i = 0; i < 7; i++) {
      final day = weekStart.add(Duration(days: i));
      week.add(await _dayFromLocalOrToday(day, today));
    }
    calendarWeek = week;

    final firstOfMonth = DateTime(today.year, today.month, 1);
    final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
    final month = <DaySteps>[];
    for (var d = 1; d <= daysInMonth; d++) {
      final day = DateTime(today.year, today.month, d);
      month.add(await _dayFromLocalOrToday(day, today));
    }
    calendarMonth = month;

    final leading = firstOfMonth.weekday - DateTime.monday;
    calendarMonthGrid = [
      for (var i = 0; i < leading; i++) null,
      ...month,
    ];
  }

  Future<DaySteps> _dayFromLocalOrToday(DateTime day, DateTime today) async {
    if (_isSameDay(day, today)) {
      return DaySteps(day, todaySteps);
    }
    if (day.isAfter(today)) {
      return DaySteps(day, null);
    }
    final snap = await StepsDayHistory.readSnapshot(day);
    return DaySteps(day, snap);
  }

  Future<void> _mergeHealthIntoCalendar(DateTime now) async {
    if (!healthAuthorized) return;
    final today = _dateOnly(now);

    Future<DaySteps> merge(DaySteps entry) async {
      if (entry.date.isAfter(today)) return entry;
      final dayStart = entry.date;
      final dayEnd = _isSameDay(dayStart, today)
          ? now
          : dayStart
              .add(const Duration(days: 1))
              .subtract(const Duration(milliseconds: 1));
      final healthSteps =
          await _health.getTotalStepsInInterval(dayStart, dayEnd);
      if (healthSteps == null) return entry;
      final local = entry.steps ?? 0;
      final best = healthSteps > local ? healthSteps : local;
      if (_isSameDay(dayStart, today)) {
        todaySteps = best > todaySteps ? best : todaySteps;
      }
      return DaySteps(dayStart, best);
    }

    calendarWeek = [
      for (final d in calendarWeek) await merge(d),
    ];
    calendarMonth = [
      for (final d in calendarMonth) await merge(d),
    ];

    final leading = calendarMonthGrid.indexWhere((e) => e != null);
    if (leading < 0) return;
    final mergedMonth = calendarMonth;
    calendarMonthGrid = [
      for (var i = 0; i < leading; i++) null,
      ...mergedMonth,
    ];
  }

  Future<void> _computeStreakDays() async {
    final today = _dateOnly(DateTime.now());
    var streak = 0;
    var cursor = todaySteps >= dailyGoal
        ? today
        : today.subtract(const Duration(days: 1));

    for (var i = 0; i < 400; i++) {
      if (cursor.isBefore(today.subtract(const Duration(days: 400)))) break;
      final steps = _isSameDay(cursor, today)
          ? todaySteps
          : await StepsDayHistory.readSnapshot(cursor);
      if (steps == null) break;
      if (steps < dailyGoal) break;
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    _streakDays = streak;
  }

  int? sumSteps(List<DaySteps> days) {
    var any = false;
    var sum = 0;
    for (final d in days) {
      if (d.steps == null) continue;
      any = true;
      sum += d.steps!;
    }
    return any ? sum : null;
  }

  int? averageSteps(List<DaySteps> days) {
    var count = 0;
    var sum = 0;
    for (final d in days) {
      if (d.steps == null) continue;
      count++;
      sum += d.steps!;
    }
    if (count == 0) return null;
    return (sum / count).round();
  }

  void _recomputeStatsFromCalendar() {
    final now = DateTime.now();
    final weekPast = calendarWeek
        .where((d) => !d.date.isAfter(_dateOnly(now)) && d.steps != null)
        .toList(growable: false);
    if (weekPast.isEmpty) {
      _sevenDayAverage = 0;
      _bestDayInWeek = 0;
      return;
    }
    final sum = weekPast.fold<int>(0, (a, d) => a + d.steps!);
    _sevenDayAverage = (sum / weekPast.length).round();
    _bestDayInWeek =
        weekPast.map((d) => d.steps!).reduce((a, b) => a > b ? a : b);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
