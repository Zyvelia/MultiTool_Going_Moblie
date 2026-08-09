import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/download_job.dart';

/// Talks to modules/yt_downloader/web_server.py.
class YtApiService {
  final String baseUrl;
  final String? accessCode;
  YtApiService(this.baseUrl, {this.accessCode});

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (accessCode != null && accessCode!.isNotEmpty)
          'X-Access-Code': accessCode!,
      };

  Future<bool> checkStatus() async {
    try {
      final res =
          await http.get(_uri('/api/status')).timeout(const Duration(seconds: 6));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<DownloadJob>> fetchJobs() async {
    final res = await http.get(_uri('/api/jobs'));
    if (res.statusCode != 200) {
      throw Exception('Failed to load jobs (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['jobs'] as List)
        .map((j) => DownloadJob.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<void> queueDownload({
    required String url,
    required String format, // 'mp3' | 'mp4'
    required String type, // 'video' | 'playlist'
  }) async {
    final res = await http.post(_uri('/api/download'),
        headers: _headers,
        body: jsonEncode({'url': url, 'format': format, 'type': type}));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['error'] ?? 'Queue failed (${res.statusCode})');
    }
  }
}
