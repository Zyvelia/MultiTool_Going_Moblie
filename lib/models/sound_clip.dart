class SoundClip {
  final String id;
  final String name;

  SoundClip({required this.id, required this.name});

  factory SoundClip.fromJson(Map<String, dynamic> json) {
    return SoundClip(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown sound',
    );
  }
}
