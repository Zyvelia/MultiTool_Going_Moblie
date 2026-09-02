import 'dart:math';

/// A single message exchanged with the paired device.
class Message {
  final String id;
  final String senderId;
  final String text;
  final DateTime sentAt;
  final bool delivered;

  const Message({
    required this.id,
    required this.senderId,
    required this.text,
    required this.sentAt,
    this.delivered = false,
  });

  // sent_at is epoch seconds (a float from Python's time.time()), same
  // convention as Note.updatedAt — not an ISO string.
  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        senderId: json['sender_id'] as String,
        text: json['text'] as String,
        sentAt: DateTime.fromMillisecondsSinceEpoch(
          (((json['sent_at'] as num?)?.toDouble() ?? 0) * 1000).round(),
        ),
        delivered: json['delivered'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sender_id': senderId,
        'text': text,
        'sent_at': sentAt.millisecondsSinceEpoch / 1000,
      };

  /// Client-generated id for an outgoing message, sent to the server so
  /// it can echo the same id back — that's what lets the chat screen
  /// recognize its own optimistic send in the broadcast instead of
  /// showing it twice.
  static String newId() {
    final rand = Random.secure();
    return List.generate(16, (_) => rand.nextInt(16).toRadixString(16)).join();
  }
}
