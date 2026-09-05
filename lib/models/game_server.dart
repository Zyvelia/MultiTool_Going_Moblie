class GameServer {
  final String id;
  final String name;
  final String gameType;
  final bool running;
  final bool ready;
  final List<String> players;

  GameServer({
    required this.id,
    required this.name,
    required this.gameType,
    required this.running,
    required this.ready,
    required this.players,
  });

  factory GameServer.fromJson(Map<String, dynamic> json) {
    final rawPlayers = json['players'];
    final players = <String>[];
    if (rawPlayers is List) {
      for (final p in rawPlayers) {
        players.add(p.toString());
      }
    }
    return GameServer(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Server',
      gameType: json['game_type'] as String? ?? '',
      running: json['running'] == true,
      ready: json['ready'] == true,
      players: players,
    );
  }

  String get statusLabel {
    if (ready) return 'Ready';
    if (running) return 'Starting';
    return 'Stopped';
  }
}
