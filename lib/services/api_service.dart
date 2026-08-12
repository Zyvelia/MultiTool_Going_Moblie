import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';

/// Thin wrapper around the endpoints exposed by
/// modules/media_player/web_server.py on the desktop app.
///
/// This app is its own independent player (same model as the browser
/// page): it streams audio directly from /api/stream/<id> into its own
/// player. It does not call /api/control — that endpoint drives the
/// desktop app's own playback engine, a separate listening session.
class ApiService {
  final String baseUrl;

  ApiService(this.baseUrl);

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('$baseUrl$path').replace(queryParameters: query);
  }

  Future<bool> checkStatus() async {
    try {
      final res = await http
          .get(_uri('/api/status'))
          .timeout(const Duration(seconds: 6));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<({List<Song> songs, int total, bool hasMore})> fetchSongs({
    String query = '',
    int offset = 0,
    int limit = 100,
  }) async {
    final res = await http.get(_uri('/api/songs', {
      'q': query,
      'offset': '$offset',
      'limit': '$limit',
    }));
    if (res.statusCode != 200) {
      throw Exception('Failed to load songs (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final songs = (data['songs'] as List)
        .map((s) => Song.fromJson(s as Map<String, dynamic>))
        .toList();
    return (
      songs: songs,
      total: data['total'] as int,
      hasMore: data['has_more'] as bool,
    );
  }

  /// URL to stream a given song's audio bytes (Range requests supported
  /// server-side, so seeking works fine with just_audio).
  String streamUrl(int songId) => '$baseUrl/api/stream/$songId';
}
