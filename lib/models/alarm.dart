class Alarm {
  Alarm({
    required this.id,
    required this.hour,
    required this.minute,
    this.label = 'Alarm',
    this.soundRef = 'builtin:klaxon',
    this.repeatWeekdays = const {},
    this.enabled = true,
  });

  final String id;
  final int hour;
  final int minute;
  final String label;
  /// `builtin:<id>` or `custom:<filename>` under app alarm_sounds dir.
  final String soundRef;
  /// Dart [DateTime.weekday] values (1 = Mon … 7 = Sun). Empty = one-shot.
  final Set<int> repeatWeekdays;
  final bool enabled;

  bool get repeats => repeatWeekdays.isNotEmpty;

  Alarm copyWith({
    String? id,
    int? hour,
    int? minute,
    String? label,
    String? soundRef,
    Set<int>? repeatWeekdays,
    bool? enabled,
  }) {
    return Alarm(
      id: id ?? this.id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      label: label ?? this.label,
      soundRef: soundRef ?? this.soundRef,
      repeatWeekdays: repeatWeekdays ?? this.repeatWeekdays,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'hour': hour,
        'minute': minute,
        'label': label,
        'soundRef': soundRef,
        'repeatWeekdays': repeatWeekdays.toList(),
        'enabled': enabled,
      };

  static Alarm fromJson(Map<String, dynamic> json) {
    final rawDays = json['repeatWeekdays'];
    final days = <int>{};
    if (rawDays is List) {
      for (final d in rawDays) {
        if (d is int) days.add(d);
      }
    }
    return Alarm(
      id: json['id'] as String,
      hour: json['hour'] as int? ?? 0,
      minute: json['minute'] as int? ?? 0,
      label: json['label'] as String? ?? 'Alarm',
      soundRef: json['soundRef'] as String? ?? 'builtin:klaxon',
      repeatWeekdays: days,
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}
