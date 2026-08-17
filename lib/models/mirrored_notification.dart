class MirroredNotification {
  final int id;
  final int seq;
  final String appName;
  final String? appId;
  final String title;
  final String body;
  final int timestampMs;
  final bool hasActions;
  final bool updated;

  MirroredNotification({
    required this.id,
    required this.seq,
    required this.appName,
    required this.appId,
    required this.title,
    required this.body,
    required this.timestampMs,
    required this.hasActions,
    required this.updated,
  });

  factory MirroredNotification.fromJson(Map<String, dynamic> json) {
    return MirroredNotification(
      id: (json['id'] as num).toInt(),
      seq: (json['seq'] as num?)?.toInt() ?? 0,
      appName: json['app_name'] as String? ?? 'Unknown App',
      appId: json['app_id'] as String?,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      // PC side sends either epoch-ms (fallback) or raw WinRT FILETIME
      // ticks (100ns since 1601) when available — normalize here so the
      // UI never has to think about which one it got.
      timestampMs: _normalizeTimestamp(json['timestamp']),
      hasActions: json['has_actions'] as bool? ?? false,
      updated: json['updated'] as bool? ?? false,
    );
  }

  static int _normalizeTimestamp(dynamic raw) {
    if (raw == null) return DateTime.now().millisecondsSinceEpoch;
    final value = (raw as num).toInt();
    // FILETIME ticks are enormous compared to epoch-ms (100ns since
    // 1601 vs ms since 1970) — anything this large came from WinRT's
    // creation_time and needs converting; anything smaller was already
    // our own epoch-ms fallback.
    const filetimeEpochDiffMs = 11644473600000;
    const ticksPerMs = 10000;
    if (value > 100000000000000) {
      return (value ~/ ticksPerMs) - filetimeEpochDiffMs;
    }
    return value;
  }

  DateTime get timestamp => DateTime.fromMillisecondsSinceEpoch(timestampMs);
}
