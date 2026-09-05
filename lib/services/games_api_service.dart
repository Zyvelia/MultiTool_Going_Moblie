import 'dart:convert';
import '../models/game.dart';
import 'trusted_http.dart';
import 'user_facing_error.dart';

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
          await trustedHttp.get(_uri('/api/status')).timeout(const Duration(seconds: 6));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<Game>> fetchGames() async {
    final res = await trustedHttp.get(_uri('/api/games'));
    if (res.statusCode != 200) {
      throw AppIssue.fromHttp(res.statusCode, res.body, doing: 'load your game list');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['games'] as List)
        .map((g) => Game.fromJson(g as Map<String, dynamic>))
        .toList();
  }

  /// Throws with a readable message on failure (wrong access code,
  /// missing exe, etc).
  Future<void> launch(String gameId) async {
    final res = await trustedHttp.post(_uri('/api/launch'),
        headers: _headers, body: jsonEncode({'id': gameId}));
    ensureOk(res, doing: 'launch that game', requireOk: true);
  }

  Future<void> rescan() async {
    final res = await trustedHttp.post(_uri('/api/rescan'), headers: _headers);
    ensureOk(res, doing: 'rescan games on the PC');
  }
}
