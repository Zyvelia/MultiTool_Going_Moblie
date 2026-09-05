import 'dart:convert';
import 'package:http/http.dart' as http;
import 'user_facing_error.dart';

/// Talks to modules/Network/Tailnet Social/web_server.py on :8450.
class SocialApiService {
  final String baseUrl;
  final String inviteKey;
  SocialApiService(this.baseUrl, {required this.inviteKey});

  Uri _uri(String path) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: {'key': inviteKey});

  Map<String, String> get _headers => {'Content-Type': 'application/json'};

  Future<List<Map<String, dynamic>>> fetchQueue() async {
    final res = await http.get(_uri('/api/queue')).timeout(const Duration(seconds: 10));
    ensureOk(res, doing: 'load the jukebox queue', requireOk: true);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['queue'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<String>> fetchSounds() async {
    final res = await http.get(_uri('/api/sounds')).timeout(const Duration(seconds: 10));
    ensureOk(res, doing: 'load soundboard clips', requireOk: true);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['sounds'] as List? ?? []).map((e) => e.toString()).toList();
  }

  Future<void> addToQueue(String title) async {
    await _post('/api/queue', {'title': title});
  }

  Future<void> playSound(String name) async {
    await _post('/api/sound', {'name': name});
  }

  Future<String> sendConsole(String server, String command) async {
    final res = await http
        .post(
          _uri('/api/console'),
          headers: _headers,
          body: jsonEncode({'server': server, 'command': command}),
        )
        .timeout(const Duration(seconds: 15));
    ensureOk(res, doing: 'send that console command', requireOk: true);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['sent']?.toString() ?? command;
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    final res = await http
        .post(_uri(path), headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    ensureOk(res, doing: 'talk to the Night page', requireOk: true);
  }
}
