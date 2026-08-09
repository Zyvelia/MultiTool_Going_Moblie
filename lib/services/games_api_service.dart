import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/game.dart';

/// Talks to modules/gaming_hub/web_server.py.
class GamesApiService {
  final String baseUrl;
  final String? accessCode;
  GamesApiService(this.baseUrl, {this.accessCode});

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

  Future<List<Game>> fetchGames() async {
    final res = await http.get(_uri('/api/games'));
    if (res.statusCode != 200) {
      throw Exception('Failed to load games (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['games'] as List)
        .map((g) => Game.fromJson(g as Map<String, dynamic>))
        .toList();
  }

  /// Throws with a readable message on failure (wrong access code,
  /// missing exe, etc).
  Future<void> launch(String gameId) async {
    final res = await http.post(_uri('/api/launch'),
        headers: _headers, body: jsonEncode({'id': gameId}));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || data['ok'] != true) {
      throw Exception(data['error'] ?? 'Launch failed (${res.statusCode})');
    }
  }

  Future<void> rescan() async {
    final res = await http.post(_uri('/api/rescan'), headers: _headers);
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      throw Exception(data['error'] ?? 'Rescan failed (${res.statusCode})');
    }
  }
}
