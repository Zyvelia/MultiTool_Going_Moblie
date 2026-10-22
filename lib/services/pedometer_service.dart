import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'steps_activity_permission.dart';
import 'steps_day_history.dart';

/// Built-in step sensor (motion chip) — what "Allow tracking" style apps use.
///
/// Count is **since last phone reboot** on the sensor; we subtract a daily
/// baseline saved the first time we see steps each calendar day.
class PedometerService extends ChangeNotifier {
  PedometerService._();

  static final PedometerService instance = PedometerService._();

  static const _trackingKey = 'steps_allow_tracking';
  static const _baselineDayKey = 'pedometer_baseline_day';
  static const _baselineStepsKey = 'pedometer_baseline_steps';

  StreamSubscription<StepCount>? _stepSub;
  StreamSubscription<PedestrianStatus>? _statusSub;

  bool allowTracking = true;
  bool listening = false;
  bool sensorAvailable = true;
  bool activityPermissionDenied = false;
  String? errorMessage;
  String pedestrianStatus = 'unknown';
  int todaySteps = 0;
  bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    allowTracking = prefs.getBool(_trackingKey) ?? true;
  }

  Future<void> setAllowTracking(bool value) async {
    allowTracking = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_trackingKey, value);
    if (value) {
      await start();
    } else {
      await stop();
      todaySteps = 0;
    }
    notifyListeners();
  }

  Future<void> start() async {
    if (!isSupported || !allowTracking || listening) return;
    await loadPrefs();
    errorMessage = null;
    sensorAvailable = true;
    activityPermissionDenied = false;

    if (Platform.isAndroid) {
      final granted = await StepsActivityPermission.ensureGranted();
      if (!granted) {
        activityPermissionDenied = true;
        final st = await StepsActivityPermission.status();
        errorMessage = StepsActivityPermission.userMessage(st);
        listening = false;
        notifyListeners();
        return;
      }
    }

    await stop();

    try {
      _stepSub = Pedometer.stepCountStream.listen(
        _onStepCount,
        onError: _onError,
      );
      _statusSub = Pedometer.pedestrianStatusStream.listen(
        (s) {
          pedestrianStatus = s.status;
          notifyListeners();
        },
        onError: (_) {},
      );
      listening = true;
      notifyListeners();
    } catch (e) {
      _onError(e);
    }
  }

  Future<void> stop() async {
    await _stepSub?.cancel();
    await _statusSub?.cancel();
    _stepSub = null;
    _statusSub = null;
    listening = false;
  }

  void _onError(Object e) {
    sensorAvailable = false;
    errorMessage = e.toString();
    listening = false;
    notifyListeners();
  }

  Future<void> _onStepCount(StepCount event) async {
    final prefs = await SharedPreferences.getInstance();
    final dayKey = _dayKey(DateTime.now());
    final storedDay = prefs.getString(_baselineDayKey);

    if (storedDay != dayKey) {
      await prefs.setString(_baselineDayKey, dayKey);
      await prefs.setInt(_baselineStepsKey, event.steps);
    }

    final baseline = prefs.getInt(_baselineStepsKey) ?? event.steps;
    todaySteps = (event.steps - baseline).clamp(0, 1_000_000);
    // ignore: unawaited_futures
    StepsDayHistory.saveSnapshot(DateTime.now(), todaySteps);
    notifyListeners();
  }

  String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
