import 'dart:convert';
import '../models/game_server.dart';
import 'trusted_http.dart';
import 'user_facing_error.dart';

/// Talks to modules/Gaming/Game Server Manager/web_server.py on :8453.
class GsmApiService {
  final String baseUrl;
  final String? accessCode;
  GsmApiService(this.baseUrl, {this.accessCode});

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (accessCode != null && accessCode!.isNotEmpty)
          'X-Access-Code': accessCode!,
      };

  Future<bool> checkStatus() async {
    try {
      final res =
          await trustedHttp.get(_uri('/api/status')).timeout(const Duration(seconds: 6));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<GameServer>> fetchServers() async {
    final res = await trustedHttp
        .get(_uri('/api/servers'))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw AppIssue.fromHttp(res.statusCode, res.body, doing: 'load game servers');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['servers'] as List? ?? [])
        .map((s) => GameServer.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  Future<void> start(String id) async {
    await _post('/api/start', {'id': id});
  }

  Future<void> stop(String id) async {
    await _post('/api/stop', {'id': id});
  }

  Future<void> sendConsole(String id, String command) async {
    await _post('/api/console', {'id': id, 'command': command});
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    final res = await trustedHttp
        .post(_uri(path), headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 20));
    ensureOk(res, doing: 'talk to that game server', requireOk: true);
  }
}
