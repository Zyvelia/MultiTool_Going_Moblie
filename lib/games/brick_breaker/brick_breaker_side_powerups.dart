import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SidePowerType { megaBalls, nuke, laserRain }

class SidePowerDef {
  final SidePowerType type;
  final String label;
  final String icon;
  final String title;
  final String description;
  final Color color;

  const SidePowerDef({
    required this.type,
    required this.label,
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });
}

const _metaKey = 'zs_brick_breaker_side_meta';
const _metaVersion = 2;

const sidePowerDefs = {
  SidePowerType.megaBalls: SidePowerDef(
    type: SidePowerType.megaBalls,
    label: 'Mega',
    icon: '10',
    title: 'Mega Volley',
    description: '+10 balls to your next shot (and this volley if mid-turn).',
    color: Color(0xFFFF6BFF),
  ),
  SidePowerType.nuke: SidePowerDef(
    type: SidePowerType.nuke,
    label: 'Nuke',
    icon: '💥',
    title: 'Board Nuke',
    description: 'Destroys every breakable brick. Barriers stay.',
    color: Color(0xFFFF5252),
  ),
  SidePowerType.laserRain: SidePowerDef(
    type: SidePowerType.laserRain,
    label: 'Rain',
    icon: '⚡',
    title: 'Laser Rain',
    description: 'Triggers all lasers plus bonus cross-beams.',
    color: Color(0xFF18FFFF),
  ),
};

Map<SidePowerType, int> _starterInventory() => {
      SidePowerType.megaBalls: 1,
      SidePowerType.nuke: 1,
      SidePowerType.laserRain: 1,
    };

Map<SidePowerType, int> _emptyInventory() => {
      for (final t in SidePowerType.values) t: 0,
    };

String _dateKey(DateTime d) {
  final y = d.year;
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

String weekStartKey([DateTime? from]) {
  final n = from ?? DateTime.now();
  final local = DateTime(n.year, n.month, n.day);
  final monday = local.subtract(Duration(days: local.weekday - 1));
  return _dateKey(monday);
}

class SidePowerMeta {
  final Map<SidePowerType, int> inventory;
  final String lastChestDate;
  final String weekStart;
  final int chestsThisWeek;

  SidePowerMeta({
    required this.inventory,
    this.lastChestDate = '',
    String? weekStart,
    this.chestsThisWeek = 0,
  }) : weekStart = weekStart ?? weekStartKey();

  int count(SidePowerType type) => inventory[type] ?? 0;

  SidePowerMeta normalized() {
    final ws = weekStartKey();
    if (weekStart != ws) {
      return copyWith(weekStart: ws, chestsThisWeek: 0);
    }
    return this;
  }

  bool get chestReady => normalized().lastChestDate != _dateKey(DateTime.now());

  int get nextChestDay => math.min(7, normalized().chestsThisWeek + 1);

  bool get isWeeklyFinale => nextChestDay >= 7 && chestReady;

  Duration get timeUntilNextChest {
    if (chestReady) return Duration.zero;
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    return tomorrow.difference(now);
  }

  static SidePowerMeta _fresh() => SidePowerMeta(
        inventory: _starterInventory(),
        weekStart: weekStartKey(),
      );

  static SidePowerMeta _fromJson(Map<String, dynamic> data) {
    final inv = _emptyInventory();
    final rawInv = data['inventory'] as Map<String, dynamic>? ?? {};
    for (final t in SidePowerType.values) {
      inv[t] = (rawInv[t.name] as int? ?? 0).clamp(0, 999);
    }
    final hasAny = inv.values.any((n) => n > 0);
    if (data['v'] == _metaVersion) {
      return SidePowerMeta(
        inventory: hasAny ? inv : _starterInventory(),
        lastChestDate: data['lastChestDate'] as String? ?? '',
        weekStart: data['weekStart'] as String? ?? weekStartKey(),
        chestsThisWeek: data['chestsThisWeek'] as int? ?? 0,
      ).normalized();
    }
    var lastChestDate = '';
    final lastMs = data['lastChestOpen'] as int? ?? 0;
    if (lastMs > 0) {
      lastChestDate = _dateKey(DateTime.fromMillisecondsSinceEpoch(lastMs));
    }
    return SidePowerMeta(
      inventory: hasAny ? inv : _starterInventory(),
      lastChestDate: lastChestDate,
      weekStart: weekStartKey(),
      chestsThisWeek: lastChestDate == _dateKey(DateTime.now()) ? 1 : 0,
    ).normalized();
  }

  static Future<SidePowerMeta> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_metaKey);
    if (raw == null || raw.isEmpty) return _fresh();
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return _fresh();
      return _fromJson(data);
    } catch (_) {
      return _fresh();
    }
  }

  Future<void> save() async {
    final n = normalized();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _metaKey,
      jsonEncode({
        'v': _metaVersion,
        'inventory': {for (final e in n.inventory.entries) e.key.name: e.value},
        'lastChestDate': n.lastChestDate,
        'weekStart': n.weekStart,
        'chestsThisWeek': n.chestsThisWeek,
      }),
    );
  }

  SidePowerMeta copyWith({
    Map<SidePowerType, int>? inventory,
    String? lastChestDate,
    String? weekStart,
    int? chestsThisWeek,
  }) {
    return SidePowerMeta(
      inventory: inventory ?? Map<SidePowerType, int>.from(this.inventory),
      lastChestDate: lastChestDate ?? this.lastChestDate,
      weekStart: weekStart ?? this.weekStart,
      chestsThisWeek: chestsThisWeek ?? this.chestsThisWeek,
    );
  }
}

Map<SidePowerType, int> pickChestRewards(
  math.Random rng, {
  required bool lastDailyOfWeek,
}) {
  const pool = [
    SidePowerType.megaBalls,
    SidePowerType.megaBalls,
    SidePowerType.laserRain,
    SidePowerType.laserRain,
  ];
  final out = _emptyInventory();
  if (lastDailyOfWeek) {
    out[SidePowerType.nuke] = 1;
    final extras = 1 + (rng.nextDouble() < 0.5 ? 1 : 0);
    for (var i = 0; i < extras; i++) {
      final t = pool[rng.nextInt(pool.length)];
      out[t] = (out[t] ?? 0) + 1;
    }
    return out;
  }
  final count = 1 + (rng.nextDouble() < 0.55 ? 1 : 0);
  for (var i = 0; i < count; i++) {
    final t = pool[rng.nextInt(pool.length)];
    out[t] = (out[t] ?? 0) + 1;
  }
  return out;
}

String formatChestStatus(SidePowerMeta meta) {
  final n = meta.normalized();
  if (n.chestReady) {
    final day = n.nextChestDay;
    return day >= 7 ? 'Day 7!' : 'Day $day/7';
  }
  final d = n.timeUntilNextChest;
  if (d.inHours >= 1) return '${d.inHours}h';
  return '${math.max(1, d.inMinutes)}m';
}
