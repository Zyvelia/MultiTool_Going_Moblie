import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/shared_file.dart';
import 'trusted_http.dart';
import 'user_facing_error.dart';

/// Wraps modules/quick_send/web_server.py — phone-to-PC upload and
/// PC-to-phone browse/download, LocalSend-style but scoped to your own
/// Tailscale mesh instead of local-network discovery.
class QuickSendApiService {
  final String baseUrl;

  QuickSendApiService(this.baseUrl);

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<bool> checkStatus() async {
    try {
      final res = await trustedHttp
          .get(_uri('/api/status'))
          .timeout(const Duration(seconds: 6));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<SharedFile>> fetchOutbox() async {
    final res = await trustedHttp.get(_uri('/api/outbox'));
    if (res.statusCode != 200) {
      throw AppIssue.fromHttp(res.statusCode, res.body, doing: 'load files from the PC');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['files'] as List)
        .map((f) => SharedFile.fromJson(f as Map<String, dynamic>))
        .toList();
  }

  /// Uploads a file already sitting on the phone's filesystem (from the
  /// file picker) to the PC's Inbox folder.
  Future<void> sendFile(String localPath, {String? filenameOverride}) async {
    final file = File(localPath);
    final request = http.MultipartRequest('POST', _uri('/api/send'));
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        localPath,
        filename: filenameOverride ?? file.uri.pathSegments.last,
      ),
    );
    final streamed = await trustedHttp.send(request);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw AppIssue.fromHttp(res.statusCode, res.body, doing: 'send that file to the PC');
    }
  }

  /// Same streamed-download-with-progress shape as
  /// YtApiService.downloadJobFile — downloads a shared file from the
  /// PC's Outbox into a local path (caller then hands it to the share
  /// sheet to actually save it into Files/Photos).
  Future<void> downloadOutboxFile({
    required String name,
    required String savePath,
    void Function(double progress)? onProgress,
  }) async {
    final req = http.Request('GET', _uri('/api/outbox/${Uri.encodeComponent(name)}'));
    final streamed = await trustedHttp.send(req);
    if (streamed.statusCode != 200) {
      throw AppIssue.fromHttp(streamed.statusCode, '', doing: 'download that file');
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
