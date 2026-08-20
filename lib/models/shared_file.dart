class SharedFile {
  final String name;
  final int size;
  final double modified; // unix seconds
  final String kind; // image | video | file

  SharedFile({
    required this.name,
    required this.size,
    required this.modified,
    this.kind = 'file',
  });

  bool get isImage => kind == 'image';
  bool get isVideo => kind == 'video';
  bool get isMedia => isImage || isVideo;

  factory SharedFile.fromJson(Map<String, dynamic> json) {
    return SharedFile(
      name: json['name'] as String,
      size: (json['size'] as num).toInt(),
      modified: (json['modified'] as num).toDouble(),
      kind: (json['kind'] as String?) ?? _kindFromName(json['name'] as String),
    );
  }

  static String _kindFromName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return 'file';
    final ext = name.substring(dot + 1).toLowerCase();
    const images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp', 'tif', 'tiff'};
    const videos = {'mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm', '3gp'};
    if (images.contains(ext)) return 'image';
    if (videos.contains(ext)) return 'video';
    return 'file';
  }
}
