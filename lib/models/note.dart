class NoteLink {
  final String label;
  final String url;

  NoteLink({required this.label, required this.url});

  factory NoteLink.fromJson(Map<String, dynamic> json) {
    return NoteLink(
      label: json['label'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'label': label, 'url': url};
}

class Note {
  final String id;
  final String title;
  final String body;
  final List<NoteLink> links;
  final double updatedAt;
  final bool pinned;

  Note({
    required this.id,
    required this.title,
    required this.body,
    required this.links,
    required this.updatedAt,
    required this.pinned,
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled',
      body: json['body'] as String? ?? '',
      links: (json['links'] as List? ?? [])
          .map((l) => NoteLink.fromJson(l as Map<String, dynamic>))
          .toList(),
      updatedAt: (json['updated_at'] as num?)?.toDouble() ?? 0,
      pinned: json['pinned'] as bool? ?? false,
    );
  }
}
