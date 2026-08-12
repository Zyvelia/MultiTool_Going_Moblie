import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import '../models/now_playing.dart';

/// Thin wrapper around the endpoints exposed by
/// modules/media_player/web_server.py on the desktop app.
///
/// This app supports two playback modes: "Phone" streams audio from
/// /api/stream/<id> into its own local player, independent of whatever
/// the desktop is doing. "PC" instead drives the desktop's own playback
/// engine via /api/now-playing and /api/control, so audio plays out of
/// the PC's speakers and the phone acts purely as a remote.
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

  /// Current state of the desktop app's own player — used in "PC" mode,
  /// where the phone controls that separate playback session instead of
  /// streaming audio locally. Polled on an interval by LibraryScreen.
  Future<NowPlaying> nowPlaying() async {
    final res = await http
        .get(_uri('/api/now-playing'))
        .timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch now-playing (${res.statusCode})');
    }
    return NowPlaying.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Sends a command to the desktop app's own player. [action] is one of
  /// 'play_song' (requires [songId]), 'play', 'pause', 'next', 'prev',
  /// or 'seek' (requires [value], in seconds — the desktop endpoint reads
  /// this under the key "value", not "position").
  Future<void> control(String action, {int? songId, double? value}) async {
    final body = <String, dynamic>{'action': action};
    if (songId != null) body['song_id'] = songId;
    if (value != null) body['value'] = value;
    final res = await http
        .post(
          _uri('/api/control'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) {
      String message = 'status ${res.statusCode}';
      try {
        final parsed = jsonDecode(res.body) as Map<String, dynamic>;
        if (parsed['error'] is String) message = parsed['error'] as String;
      } catch (_) {
        // Body wasn't JSON — fall back to the status code above.
      }
      throw Exception(message);
    }
  }
}
