import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../models/reminder.dart';
import 'local_notification_service.dart';

/// Local reminders — persisted on device and fired via scheduled OS
/// notifications (plus an in-app dialog when the app is open).
class ReminderService {
  ReminderService._();
  static final instance = ReminderService._();

  static const _prefsKey = 'reminders_v1';

  final ValueNotifier<List<Reminder>> reminders = ValueNotifier([]);

  Timer? _foregroundTimer;
  final Set<String> _inAppShown = {};

  Future<void> init() async {
    await LocalNotificationService.instance.ensureTimezoneReady();
    await _load();
    await rescheduleAll();
    _foregroundTimer?.cancel();
    _foregroundTimer = Timer.periodic(const Duration(seconds: 20), (_) => _checkForegroundAlerts());
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      reminders.value = [];
      return;
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      reminders.value = list
          .whereType<Map>()
          .map((e) => Reminder.fromJson(Map<String, dynamic>.from(e)))
          .toList()
        ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    } catch (_) {
      reminders.value = [];
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(reminders.value.map((r) => r.toJson()).toList());
    await prefs.setString(_prefsKey, encoded);
  }

  Future<Reminder> add({
    required String text,
    required DateTime dueAt,
    int nudgeMinutesBefore = 5,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Reminder text cannot be empty');
    }
    if (!dueAt.isAfter(DateTime.now())) {
      throw ArgumentError('Pick a date and time in the future');
    }
    final item = Reminder(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: trimmed,
      dueAt: dueAt,
      nudgeMinutesBefore: nudgeMinutesBefore,
    );
    reminders.value = [...reminders.value, item]..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    await _save();
    await _scheduleOne(item);
    return item;
  }

  Future<void> toggleCompleted(String id, bool completed) async {
    final next = reminders.value.map((r) {
      if (r.id != id) return r;
      return r.copyWith(completed: completed, enabled: !completed);
    }).toList();
    reminders.value = next;
    await _save();
    final item = next.firstWhere((r) => r.id == id);
    if (completed) {
      await LocalNotificationService.instance.cancelReminder(item.id);
    } else if (item.dueAt.isAfter(DateTime.now())) {
      await _scheduleOne(item);
    }
  }

  Future<void> update({
    required String id,
    required String text,
    required DateTime dueAt,
    int nudgeMinutesBefore = 5,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Reminder text cannot be empty');
    }
    if (!dueAt.isAfter(DateTime.now())) {
      throw ArgumentError('Pick a date and time in the future');
    }
    await LocalNotificationService.instance.cancelReminder(id);
    reminders.value = reminders.value.map((r) {
      if (r.id != id) return r;
      return r.copyWith(
        text: trimmed,
        dueAt: dueAt,
        nudgeMinutesBefore: nudgeMinutesBefore,
        completed: false,
        enabled: true,
      );
    }).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    _inAppShown.removeWhere((k) => k.startsWith('$id:'));
    await _save();
    final item = reminders.value.firstWhere((r) => r.id == id);
    await _scheduleOne(item);
  }

  Future<void> snooze(String id, Duration delay) async {
    final r = reminders.value.cast<Reminder?>().firstWhere(
          (x) => x?.id == id,
          orElse: () => null,
        );
    if (r == null) return;
    final dueAt = DateTime.now().add(delay);
    await update(
      id: id,
      text: r.text,
      dueAt: dueAt,
      nudgeMinutesBefore: r.nudgeMinutesBefore,
    );
  }

  Future<void> rescheduleAll() => _rescheduleAll();

  Future<void> delete(String id) async {
    await LocalNotificationService.instance.cancelReminder(id);
    reminders.value = reminders.value.where((r) => r.id != id).toList();
    _inAppShown.remove(id);
    await _save();
  }

  Future<void> _rescheduleAll() async {
    for (final r in reminders.value) {
      if (r.enabled && !r.completed && r.dueAt.isAfter(DateTime.now())) {
        await _scheduleOne(r);
      } else {
        await LocalNotificationService.instance.cancelReminder(r.id);
      }
    }
  }

  Future<void> _scheduleOne(Reminder r) async {
    await LocalNotificationService.instance.scheduleReminder(
      reminderId: r.id,
      title: 'Reminder',
      body: r.text,
      dueAt: r.dueAt,
      nudgeMinutesBefore: r.nudgeMinutesBefore,
    );
  }

  void _checkForegroundAlerts() {
    final now = DateTime.now();
    for (final r in reminders.value) {
      if (!r.enabled || r.completed) continue;
      final due = r.dueAt;
      final nudgeAt = due.subtract(Duration(minutes: r.nudgeMinutesBefore));
      final showNudge = !now.isBefore(nudgeAt) && now.isBefore(due);
      final showDue = !now.isBefore(due) && now.isBefore(due.add(const Duration(minutes: 2)));
      if (!showNudge && !showDue) continue;
      final key = '${r.id}:${showDue ? 'due' : 'nudge'}';
      if (_inAppShown.contains(key)) continue;
      _inAppShown.add(key);
      _showInAppDialog(r, isDue: showDue);
    }
  }

  void _showInAppDialog(Reminder r, {required bool isDue}) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    final when = MaterialLocalizations.of(ctx).formatFullDate(r.dueAt);
    final time = MaterialLocalizations.of(ctx).formatTimeOfDay(
      TimeOfDay.fromDateTime(r.dueAt),
    );
    showDialog<void>(
      context: ctx,
      builder: (context) => AlertDialog(
        title: Text(isDue ? 'Reminder' : 'Coming up soon'),
        content: Text(
          isDue ? r.text : '${r.text}\n\nDue $when at $time',
        ),
        actions: [
          if (isDue)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                snooze(r.id, const Duration(minutes: 10));
              },
              child: const Text('Snooze 10m'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          if (isDue)
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                toggleCompleted(r.id, true);
              },
              child: const Text('Done'),
            ),
        ],
      ),
    );
  }
}
