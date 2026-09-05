class AiMessage {
  final String role;
  final String content;

  const AiMessage({required this.role, required this.content});

  factory AiMessage.fromJson(Map<String, dynamic> json) {
    return AiMessage(
      role: json['role'] as String? ?? 'assistant',
      content: json['content'] as String? ?? '',
    );
  }

  bool get isUser => role == 'user';
  bool get isTool => role == 'tool';
}

class AiChatStatus {
  final bool ready;
  final String source;
  final String model;
  final String error;
  final String hostedBaseUrl;
  final String lastProject;

  const AiChatStatus({
    required this.ready,
    required this.source,
    required this.model,
    required this.error,
    this.hostedBaseUrl = '',
    this.lastProject = '',
  });

  factory AiChatStatus.fromJson(Map<String, dynamic> json) {
    return AiChatStatus(
      ready: json['ready'] == true,
      source: json['source'] as String? ?? '',
      model: json['model'] as String? ?? '',
      error: json['error'] as String? ?? '',
      hostedBaseUrl: json['hosted_base_url'] as String? ?? '',
      lastProject: json['last_project'] as String? ?? '',
    );
  }
}

class AiChatReply {
  final String reply;
  final List<Map<String, dynamic>> tools;
  final bool cleared;
  final String path;

  const AiChatReply({
    required this.reply,
    required this.tools,
    this.cleared = false,
    this.path = '',
  });
}
