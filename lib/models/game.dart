class Game {
  final String id;
  final String name;
  final String launcher;

  Game({required this.id, required this.name, required this.launcher});

  factory Game.fromJson(Map<String, dynamic> json) {
    return Game(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown game',
      launcher: json['launcher'] as String? ?? 'Unknown',
    );
  }
}
