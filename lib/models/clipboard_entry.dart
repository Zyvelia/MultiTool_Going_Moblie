class ClipboardEntry {
  final String id;
  final String text;
  final double timestamp;
  final bool pinned;

  ClipboardEntry({
    required this.id,
    required this.text,
    required this.timestamp,
    required this.pinned,
  });

  factory ClipboardEntry.fromJson(Map<String, dynamic> json) {
    return ClipboardEntry(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? '',
      timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0,
      pinned: json['pinned'] as bool? ?? false,
    );
  }
}
