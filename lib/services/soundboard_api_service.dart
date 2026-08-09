import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/sound_clip.dart';

/// Talks to modules/soundboard/web_server.py. Playback happens on the
/// PC's configured output device(s) (e.g. a Bluetooth speaker paired
/// to it) — this app only ever sends a "play this id" trigger, it
/// never streams or plays audio itself.
class SoundboardApiService {
  final String baseUrl;
  final String? accessCode;
  SoundboardApiService(this.baseUrl, {this.accessCode});

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (accessCode != null && accessCode!.isNotEmpty)
          'X-Access-Code': accessCode!,
      };

  Future<Map<String, dynamic>?> fetchStatus() async {
    try {
      final res = await http
          .get(_uri('/api/status'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<List<SoundClip>> fetchSounds() async {
    final res = await http.get(_uri('/api/sounds'));
    if (res.statusCode != 200) {
      throw Exception('Failed to load sounds (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['sounds'] as List)
        .map((s) => SoundClip.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  Future<void> play(String soundId) async {
    final res = await http.post(_uri('/api/play'),
        headers: _headers, body: jsonEncode({'id': soundId}));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['error'] ?? 'Play failed (${res.statusCode})');
    }
  }

  Future<void> stopAll() async {
    final res = await http.post(_uri('/api/stop'), headers: _headers);
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(data['error'] ?? 'Stop failed (${res.statusCode})');
    }
  }
}
