class InboxMessage {
  final String id;
  final String senderName;
  final String senderEmail;
  final String text;
  final DateTime createdAt;
  final bool delivered;

  const InboxMessage({
    required this.id,
    required this.senderName,
    required this.senderEmail,
    required this.text,
    required this.createdAt,
    required this.delivered,
  });

  factory InboxMessage.fromJson(Map<String, dynamic> json) {
    final created = json['createdAt'];
    final epochMs = created is num ? created.toInt() : 0;
    return InboxMessage(
      id: '${json['id'] ?? ''}',
      senderName: '${json['senderName'] ?? 'Unknown'}',
      senderEmail: '${json['senderEmail'] ?? ''}',
      text: '${json['text'] ?? ''}',
      createdAt: DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true).toLocal(),
      delivered: json['delivered'] == true || json['delivered'] == 1,
    );
  }
}
