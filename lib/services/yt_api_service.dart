import 'dart:convert';
import 'dart:io';
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

  /// Streams a completed job's file (by index into DownloadJob.files) to
  /// [savePath], reporting 0.0–1.0 progress via [onProgress]. Throws if
  /// the file is missing/moved or the request fails.
  Future<void> downloadJobFile({
    required String jobId,
    required int index,
    required String savePath,
    void Function(double progress)? onProgress,
  }) async {
    final req = http.Request(
      'GET',
      _uri('/api/jobs/$jobId/download/$index'),
    );
    req.headers.addAll(_headers);
    final streamed = await http.Client().send(req);
    if (streamed.statusCode != 200 && streamed.statusCode != 206) {
      throw Exception('Download failed (${streamed.statusCode})');
    }

    final total = streamed.contentLength ?? 0;
    var received = 0;
    final file = await File(savePath).open(mode: FileMode.write);
    try {
      await for (final chunk in streamed.stream) {
        await file.writeFrom(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
    } finally {
      await file.close();
    }
  }
}
