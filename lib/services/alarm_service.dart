import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../models/alarm.dart';
import '../screens/alarm_ring_screen.dart';
import 'alarm_sound_catalog.dart';
import 'alarm_sound_player.dart';
import 'local_notification_service.dart';

class AlarmService {
  AlarmService._();
  static final instance = AlarmService._();

  static const _prefsKey = 'alarms_v1';

  final ValueNotifier<List<Alarm>> alarms = ValueNotifier([]);
  Timer? _tick;
  final Set<String> _firedKeys = {};

  Future<void> init() async {
    await AlarmSoundCatalog.instance.load();
    await _load();
    await rescheduleAll();
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 8), (_) => _checkDueAlarms());
    final pending = LocalNotificationService.instance.consumePendingAlarmId();
    if (pending != null) {
      await ringFromNotification(pending);
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      alarms.value = [];
      return;
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      alarms.value = list
          .whereType<Map>()
          .map((e) => Alarm.fromJson(Map<String, dynamic>.from(e)))
          .toList()
        ..sort((a, b) => a.hour * 60 + a.minute - (b.hour * 60 + b.minute));
    } catch (_) {
      alarms.value = [];
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(alarms.value.map((a) => a.toJson()).toList()),
    );
  }

  Future<Alarm> add({
    required int hour,
    required int minute,
    String label = 'Alarm',
    String soundRef = 'builtin:klaxon',
    Set<int> repeatWeekdays = const {},
  }) async {
    final alarm = Alarm(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      hour: hour,
      minute: minute,
      label: label.trim().isEmpty ? 'Alarm' : label.trim(),
      soundRef: soundRef,
      repeatWeekdays: repeatWeekdays,
    );
    alarms.value = [...alarms.value, alarm]..sort((a, b) => a.hour * 60 + a.minute - (b.hour * 60 + b.minute));
    await _save();
    await _scheduleOne(alarm);
    return alarm;
  }

  Future<void> update(Alarm alarm) async {
    alarms.value = alarms.value.map((a) => a.id == alarm.id ? alarm : a).toList()
      ..sort((a, b) => a.hour * 60 + a.minute - (b.hour * 60 + b.minute));
    await _save();
    await LocalNotificationService.instance.cancelAlarm(alarm.id);
    if (alarm.enabled) {
      await _scheduleOne(alarm);
    }
  }

  Future<void> delete(String id) async {
    await LocalNotificationService.instance.cancelAlarm(id);
    alarms.value = alarms.value.where((a) => a.id != id).toList();
    await _save();
  }

  Future<void> toggle(String id, bool enabled) async {
    final list = alarms.value.map((a) => a.id == id ? a.copyWith(enabled: enabled) : a).toList();
    alarms.value = list;
    await _save();
    final alarm = list.firstWhere((a) => a.id == id);
    if (enabled) {
      await _scheduleOne(alarm);
    } else {
      await LocalNotificationService.instance.cancelAlarm(id);
    }
  }

  DateTime? nextOccurrence(Alarm alarm, DateTime from) {
    if (!alarm.enabled) return null;
    final today = DateTime(from.year, from.month, from.day, alarm.hour, alarm.minute);
    if (alarm.repeatWeekdays.isEmpty) {
      if (today.isAfter(from)) return today;
      final tomorrow = today.add(const Duration(days: 1));
      return tomorrow;
    }
    for (var i = 0; i < 8; i++) {
      final day = from.add(Duration(days: i));
      final candidate = DateTime(day.year, day.month, day.day, alarm.hour, alarm.minute);
      if (!candidate.isAfter(from)) continue;
      if (alarm.repeatWeekdays.contains(candidate.weekday)) return candidate;
    }
    return null;
  }

  Future<void> _scheduleOne(Alarm alarm) async {
    final when = nextOccurrence(alarm, DateTime.now());
    if (when == null) return;
    await LocalNotificationService.instance.scheduleAlarm(
      alarmId: alarm.id,
      title: alarm.label,
      body: 'Tap to open alarm — sound keeps until you stop it',
      at: when,
    );
  }

  Future<void> rescheduleAll() async => _rescheduleAll();

  Future<void> _rescheduleAll() async {
    for (final a in alarms.value) {
      if (a.enabled) {
        await _scheduleOne(a);
      } else {
        await LocalNotificationService.instance.cancelAlarm(a.id);
      }
    }
  }

  void _checkDueAlarms() {
    final now = DateTime.now();
    for (final alarm in alarms.value) {
      if (!alarm.enabled) continue;
      if (now.hour != alarm.hour || now.minute != alarm.minute) continue;
      final key = _fireKey(alarm, now);
      if (_firedKeys.contains(key)) continue;
      _firedKeys.add(key);
      ring(alarm.id);
    }
  }

  String _fireKey(Alarm alarm, DateTime now) =>
      '${alarm.id}:${now.year}-${now.month}-${now.day}-${now.hour}:${now.minute}';

  Future<void> ringFromNotification(String alarmId) async {
    await ring(alarmId);
  }

  Future<void> ring(String alarmId) async {
    Alarm? alarm;
    for (final a in alarms.value) {
      if (a.id == alarmId) {
        alarm = a;
        break;
      }
    }
    if (alarm == null) return;
    await AlarmSoundPlayer.instance.startAlarmLoop(alarm.soundRef);
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    final route = ModalRoute.of(ctx);
    if (route != null && route.settings.name == 'alarm_ring') return;
    await Navigator.of(ctx).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'alarm_ring'),
        fullscreenDialog: true,
        builder: (_) {
          final a = alarm!;
          return AlarmRingScreen(
            alarm: a,
            onStop: () => dismissRing(a),
            onSnooze: (minutes) => snooze(a.id, minutes),
          );
        },
      ),
    );
  }

  Future<void> snooze(String alarmId, int minutes) async {
    Alarm? alarm;
    for (final a in alarms.value) {
      if (a.id == alarmId) {
        alarm = a;
        break;
      }
    }
    if (alarm == null) return;
    await AlarmSoundPlayer.instance.stop();
    final ctx = navigatorKey.currentContext;
    if (ctx != null && Navigator.of(ctx).canPop()) {
      Navigator.of(ctx).pop();
    }
    final at = DateTime.now().add(Duration(minutes: minutes));
    await LocalNotificationService.instance.scheduleAlarm(
      alarmId: '${alarmId}_snooze_${at.millisecondsSinceEpoch}',
      title: alarm.label,
      body: 'Snoozed — tap to open',
      at: at,
      payloadAlarmId: alarmId,
    );
    if (!alarm.repeats) {
      await toggle(alarm.id, false);
    }
  }

  Future<void> dismissRing(Alarm alarm) async {
    await AlarmSoundPlayer.instance.stop();
    if (!alarm.repeats) {
      await toggle(alarm.id, false);
    } else {
      await _scheduleOne(alarm);
    }
  }
}
