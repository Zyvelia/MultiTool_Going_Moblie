class DownloadJob {
  final String id;
  final String url;
  final String format;
  final String type;
  final String status; // queued -> downloading -> done | error
  final double percent;
  final String message;

  DownloadJob({
    required this.id,
    required this.url,
    required this.format,
    required this.type,
    required this.status,
    required this.percent,
    required this.message,
  });

  factory DownloadJob.fromJson(Map<String, dynamic> json) {
    return DownloadJob(
      id: json['id'] as String? ?? '',
      url: json['url'] as String? ?? '',
      format: json['format'] as String? ?? '',
      type: json['type'] as String? ?? '',
      status: json['status'] as String? ?? 'queued',
      percent: (json['percent'] as num?)?.toDouble() ?? 0.0,
      message: json['message'] as String? ?? '',
    );
  }
}
