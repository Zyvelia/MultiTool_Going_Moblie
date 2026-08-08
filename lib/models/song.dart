class Song {
  final int id;
  final String title;
  final String artist;
  final String album;
  final int duration;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] as int,
      title: (json['title'] as String?) ?? 'Unknown title',
      artist: (json['artist'] as String?) ?? '',
      album: (json['album'] as String?) ?? '',
      duration: (json['duration'] as num?)?.toInt() ?? 0,
    );
  }
}
