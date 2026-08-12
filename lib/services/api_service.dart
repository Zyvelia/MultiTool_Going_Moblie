import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import '../models/now_playing.dart';

/// Thin wrapper around the endpoints exposed by
/// modules/media_player/web_server.py on the desktop app.
///
/// Two playback modes, both hitting this same server:
///   - "On phone": app streams audio directly from /api/stream/<id> into
///     its own local player (LockCachingAudioSource). Independent
///     listening session from the desktop.
///   - "On PC": app polls /api/now-playing and drives the desktop's own
///     playback engine via POST /api/control. No audio flows to the
///     phone at all in this mode — it's a remote for what's coming out
///     of your PC's speakers. Requires the desktop's Music Player page
///     to be open (control returns 409 otherwise).
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

  // ---------------------------------------------------------------
  // "Control PC" mode
  // ---------------------------------------------------------------

  /// Throws on network failure; a 409 (no engine attached — desktop
  /// Music Player page isn't open) surfaces as an Exception with that
  /// message so the UI can show something actionable.
  Future<NowPlaying> fetchNowPlaying() async {
    final res =
        await http.get(_uri('/api/now-playing')).timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) {
      throw Exception('now-playing failed (${res.statusCode})');
    }
    return NowPlaying.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<NowPlaying> _control(Map<String, dynamic> body) async {
    final res = await http
        .post(_uri('/api/control'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 6));
    if (res.statusCode == 409) {
      throw Exception(
          'Open the Music Player page in the desktop app first.');
    }
    if (res.statusCode != 200) {
      throw Exception('control failed (${res.statusCode})');
    }
    return NowPlaying.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<NowPlaying> pcPlay() => _control({'action': 'play'});
  Future<NowPlaying> pcPause() => _control({'action': 'pause'});
  Future<NowPlaying> pcNext() => _control({'action': 'next'});
  Future<NowPlaying> pcPrev() => _control({'action': 'prev'});
  Future<NowPlaying> pcSeek(double seconds) =>
      _control({'action': 'seek', 'value': seconds});
  Future<NowPlaying> pcPlaySong(int songId) =>
      _control({'action': 'play_song', 'song_id': songId});
}
