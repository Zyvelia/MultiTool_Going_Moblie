class Reminder {
  Reminder({
    required this.id,
    required this.text,
    required this.dueAt,
    this.nudgeMinutesBefore = 5,
    this.enabled = true,
    this.completed = false,
  });

  final String id;
  final String text;
  final DateTime dueAt;
  final int nudgeMinutesBefore;
  final bool enabled;
  final bool completed;

  bool get isPast => dueAt.isBefore(DateTime.now());

  Reminder copyWith({
    String? id,
    String? text,
    DateTime? dueAt,
    int? nudgeMinutesBefore,
    bool? enabled,
    bool? completed,
  }) {
    return Reminder(
      id: id ?? this.id,
      text: text ?? this.text,
      dueAt: dueAt ?? this.dueAt,
      nudgeMinutesBefore: nudgeMinutesBefore ?? this.nudgeMinutesBefore,
      enabled: enabled ?? this.enabled,
      completed: completed ?? this.completed,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'dueAt': dueAt.toIso8601String(),
        'nudgeMinutesBefore': nudgeMinutesBefore,
        'enabled': enabled,
        'completed': completed,
      };

  static Reminder fromJson(Map<String, dynamic> json) {
    return Reminder(
      id: json['id'] as String,
      text: json['text'] as String? ?? '',
      dueAt: DateTime.parse(json['dueAt'] as String),
      nudgeMinutesBefore: json['nudgeMinutesBefore'] as int? ?? 5,
      enabled: json['enabled'] as bool? ?? true,
      completed: json['completed'] as bool? ?? false,
    );
  }
}
