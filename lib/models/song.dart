class Song {
  final int id;
  final String title;
  final String artist;
  final String album;
  final int duration;
  // Bytes, as reported by the server's library index. 0 if the desktop
  // hasn't rescanned since this column was added, or when reconstructed
  // for an offline-cached entry that predates a known size — download
  // sizing falls back to the stream response's actual Content-Length in
  // that case, so this is only a hint, never load-bearing.
  final int size;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.size = 0,
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] as int,
      title: (json['title'] as String?) ?? 'Unknown title',
      artist: (json['artist'] as String?) ?? '',
      album: (json['album'] as String?) ?? '',
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      size: (json['size'] as num?)?.toInt() ?? 0,
    );
  }
}
