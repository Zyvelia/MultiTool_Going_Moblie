class AiApproval {
  final String id;
  final String project;
  final String agent;
  final String operation;
  final String reason;
  final String risk;
  final List<String> files;
  final String diff;
  final DateTime? expiresAt;
  final String status;

  const AiApproval({
    required this.id,
    required this.project,
    required this.agent,
    required this.operation,
    required this.reason,
    required this.risk,
    required this.files,
    required this.diff,
    required this.expiresAt,
    required this.status,
  });

  factory AiApproval.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'];
    final files = rawFiles is List
        ? rawFiles.map((e) => e.toString()).toList()
        : <String>[];
    DateTime? expires;
    final rawExpiry = json['expires_at'] ?? json['expiresAt'];
    if (rawExpiry is String) expires = DateTime.tryParse(rawExpiry);
    return AiApproval(
      id: json['id']?.toString() ?? '',
      project: json['project']?.toString() ?? '',
      agent: json['agent']?.toString() ?? '',
      operation: json['operation']?.toString() ?? json['name']?.toString() ?? 'AI operation',
      reason: json['reason']?.toString() ?? '',
      risk: json['risk']?.toString() ?? 'unknown',
      files: files,
      diff: json['diff']?.toString() ?? '',
      expiresAt: expires,
      status: json['status']?.toString() ?? 'pending',
    );
  }
}
