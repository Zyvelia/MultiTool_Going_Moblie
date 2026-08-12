/// Mirrors the JSON shape of GET /api/now-playing from
/// modules/media_player/web_server.py on the desktop app.
class NowPlaying {
  final bool attached;
  final int? songId;
  final String title;
  final String artist;
  final String album;
  final bool isPlaying;
  final double position; // seconds
  final double duration; // seconds
  final bool hasPrev;
  final bool hasNext;

  NowPlaying({
    required this.attached,
    this.songId,
    this.title = '',
    this.artist = '',
    this.album = '',
    this.isPlaying = false,
    this.position = 0,
    this.duration = 0,
    this.hasPrev = false,
    this.hasNext = false,
  });

  factory NowPlaying.notAttached() => NowPlaying(attached: false);

  factory NowPlaying.fromJson(Map<String, dynamic> json) {
    final attached = json['attached'] as bool? ?? false;
    if (!attached) return NowPlaying.notAttached();

    final song = json['song'] as Map<String, dynamic>?;
    return NowPlaying(
      attached: true,
      songId: song?['id'] as int?,
      title: (song?['title'] as String?) ?? 'Nothing playing',
      artist: (song?['artist'] as String?) ?? '',
      album: (song?['album'] as String?) ?? '',
      isPlaying: json['is_playing'] as bool? ?? false,
      position: ((json['position'] as num?) ?? 0).toDouble(),
      duration: ((json['duration'] as num?) ?? 0).toDouble(),
      hasPrev: json['has_prev'] as bool? ?? false,
      hasNext: json['has_next'] as bool? ?? false,
    );
  }
}
