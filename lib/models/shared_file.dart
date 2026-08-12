class SharedFile {
  final String name;
  final int size;
  final double modified; // unix seconds

  SharedFile({required this.name, required this.size, required this.modified});

  factory SharedFile.fromJson(Map<String, dynamic> json) {
    return SharedFile(
      name: json['name'] as String,
      size: (json['size'] as num).toInt(),
      modified: (json['modified'] as num).toDouble(),
    );
  }
}
