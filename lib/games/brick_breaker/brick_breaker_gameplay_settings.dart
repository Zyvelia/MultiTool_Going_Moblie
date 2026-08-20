import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum BrickBreakerTimeUnit { ms, sec, min }

extension BrickBreakerTimeUnitInfo on BrickBreakerTimeUnit {
  String get label {
    switch (this) {
      case BrickBreakerTimeUnit.ms:
        return 'ms';
      case BrickBreakerTimeUnit.sec:
        return 'sec';
      case BrickBreakerTimeUnit.min:
        return 'min';
    }
  }

  String get storageKey {
    switch (this) {
      case BrickBreakerTimeUnit.ms:
        return 'ms';
      case BrickBreakerTimeUnit.sec:
        return 's';
      case BrickBreakerTimeUnit.min:
        return 'min';
    }
  }

  double toMs(double value) {
    switch (this) {
      case BrickBreakerTimeUnit.ms:
        return value;
      case BrickBreakerTimeUnit.sec:
        return value * 1000;
      case BrickBreakerTimeUnit.min:
        return value * 60000;
    }
  }

  double fromMs(double ms) {
    switch (this) {
      case BrickBreakerTimeUnit.ms:
        return ms;
      case BrickBreakerTimeUnit.sec:
        return ms / 1000;
      case BrickBreakerTimeUnit.min:
        return ms / 60000;
    }
  }

  double minValue() {
    switch (this) {
      case BrickBreakerTimeUnit.ms:
        return 1000;
      case BrickBreakerTimeUnit.sec:
        return 1;
      case BrickBreakerTimeUnit.min:
        return 1;
    }
  }

  double stepValue() {
    switch (this) {
      case BrickBreakerTimeUnit.ms:
        return 1000;
      case BrickBreakerTimeUnit.sec:
        return 1;
      case BrickBreakerTimeUnit.min:
        return 1;
    }
  }
}

BrickBreakerTimeUnit brickBreakerTimeUnitFromKey(String? key) {
  switch (key) {
    case 'ms':
      return BrickBreakerTimeUnit.ms;
    case 's':
      return BrickBreakerTimeUnit.sec;
    case 'min':
    default:
      return BrickBreakerTimeUnit.min;
  }
}

class BrickBreakerTimeControlState {
  final int ms;
  final double display;
  final double min;
  final double max;
  final String label;

  const BrickBreakerTimeControlState({
    required this.ms,
    required this.display,
    required this.min,
    required this.max,
    required this.label,
  });
}

class BrickBreakerGameplaySettings {
  static const _prefsKey = 'zs_brick_breaker_gameplay';
  static const timeMsMin = 1000;
  static const delayMsMax = 30 * 60 * 1000;
  static const riseMsMax = 45 * 60 * 1000;

  bool ballRampEnabled;
  int ballRampDelayMs;
  int ballRampRiseMs;
  BrickBreakerTimeUnit ballRampDelayUnit;
  BrickBreakerTimeUnit ballRampRiseUnit;
  double ballRampMax;

  BrickBreakerGameplaySettings({
    this.ballRampEnabled = true,
    this.ballRampDelayMs = 5 * 60 * 1000,
    this.ballRampRiseMs = 10 * 60 * 1000,
    this.ballRampDelayUnit = BrickBreakerTimeUnit.min,
    this.ballRampRiseUnit = BrickBreakerTimeUnit.min,
    this.ballRampMax = 2.25,
  });

  double get ballRampDelaySec =>
      _clampTimeMs(ballRampDelayMs, delayMsMax) / 1000.0;

  double get ballRampRiseSec => _clampTimeMs(ballRampRiseMs, riseMsMax) / 1000.0;

  double get ballRampMaxClamped => ballRampMax.clamp(1.1, 25.0);

  static int _clampTimeMs(int ms, int maxMs) =>
      ms.clamp(timeMsMin, maxMs);

  String formatTimeLabel(int ms, BrickBreakerTimeUnit unit) {
    final value = unit.fromMs(ms.toDouble());
    switch (unit) {
      case BrickBreakerTimeUnit.ms:
        return '${value.round()} ms';
      case BrickBreakerTimeUnit.sec:
        final rounded = (value * 10).round() / 10;
        final text = rounded % 1 == 0 ? '${rounded.toInt()}' : '$rounded';
        return '$text sec';
      case BrickBreakerTimeUnit.min:
        return '${value.round()} min';
    }
  }

  BrickBreakerTimeControlState timeControlState({
    required int ms,
    required BrickBreakerTimeUnit unit,
    required int maxMs,
  }) {
    final clampedMs = _clampTimeMs(ms, maxMs);
    final maxDisplay = unit.fromMs(maxMs.toDouble());
    var display = unit.fromMs(clampedMs.toDouble()).clamp(unit.minValue(), maxDisplay);
    final snappedMs = _clampTimeMs(unit.toMs(display).round(), maxMs);
    display = unit.fromMs(snappedMs.toDouble());
    return BrickBreakerTimeControlState(
      ms: snappedMs,
      display: display,
      min: unit.minValue(),
      max: maxDisplay,
      label: formatTimeLabel(snappedMs, unit),
    );
  }

  BrickBreakerTimeControlState delayControlState() => timeControlState(
        ms: ballRampDelayMs,
        unit: ballRampDelayUnit,
        maxMs: delayMsMax,
      );

  BrickBreakerTimeControlState riseControlState() => timeControlState(
        ms: ballRampRiseMs,
        unit: ballRampRiseUnit,
        maxMs: riseMsMax,
      );

  void setDelayFromDisplay(double value) {
    ballRampDelayMs = _clampTimeMs(
      ballRampDelayUnit.toMs(value).round(),
      delayMsMax,
    );
  }

  void setRiseFromDisplay(double value) {
    ballRampRiseMs = _clampTimeMs(
      ballRampRiseUnit.toMs(value).round(),
      riseMsMax,
    );
  }

  int sliderDivisions(BrickBreakerTimeControlState state) {
    final span = state.max - state.min;
    if (span <= 0) return 1;
    return span.round().clamp(1, 900);
  }

  factory BrickBreakerGameplaySettings.fromJson(Map<String, dynamic> json) {
    var delayMs = (json['ballRampDelayMs'] as num?)?.toInt();
    var riseMs = (json['ballRampRiseMs'] as num?)?.toInt();
    if (delayMs == null && json['ballRampDelayMin'] != null) {
      delayMs = (json['ballRampDelayMin'] as num).toInt() * 60000;
    }
    if (riseMs == null && json['ballRampRiseMin'] != null) {
      riseMs = (json['ballRampRiseMin'] as num).toInt() * 60000;
    }
    return BrickBreakerGameplaySettings(
      ballRampEnabled: json['ballRampEnabled'] as bool? ?? true,
      ballRampDelayMs: _clampTimeMs(delayMs ?? 5 * 60 * 1000, delayMsMax),
      ballRampRiseMs: _clampTimeMs(riseMs ?? 10 * 60 * 1000, riseMsMax),
      ballRampDelayUnit: brickBreakerTimeUnitFromKey(json['ballRampDelayUnit'] as String?),
      ballRampRiseUnit: brickBreakerTimeUnitFromKey(json['ballRampRiseUnit'] as String?),
      ballRampMax: (json['ballRampMax'] as num?)?.toDouble() ?? 2.25,
    );
  }

  Map<String, dynamic> toJson() => {
        'ballRampEnabled': ballRampEnabled,
        'ballRampDelayMs': ballRampDelayMs,
        'ballRampRiseMs': ballRampRiseMs,
        'ballRampDelayUnit': ballRampDelayUnit.storageKey,
        'ballRampRiseUnit': ballRampRiseUnit.storageKey,
        'ballRampMax': ballRampMax,
      };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final parsed = BrickBreakerGameplaySettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      ballRampEnabled = parsed.ballRampEnabled;
      ballRampDelayMs = parsed.ballRampDelayMs;
      ballRampRiseMs = parsed.ballRampRiseMs;
      ballRampDelayUnit = parsed.ballRampDelayUnit;
      ballRampRiseUnit = parsed.ballRampRiseUnit;
      ballRampMax = parsed.ballRampMax;
    } catch (_) {}
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(toJson()));
  }
}
