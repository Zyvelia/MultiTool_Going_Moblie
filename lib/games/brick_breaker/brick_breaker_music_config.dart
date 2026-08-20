class BrickBreakerMusicLevel {
  final int level;
  final String asset;

  const BrickBreakerMusicLevel({required this.level, required this.asset});
}

/// Matches web/music-config.js
const brickBreakerDefaultMusic = 'assets/games/brick_breaker/music/bgm.mp3';

const brickBreakerMusicLevels = <BrickBreakerMusicLevel>[
  BrickBreakerMusicLevel(level: 10, asset: 'assets/games/brick_breaker/music/level-10.mp3'),
  BrickBreakerMusicLevel(level: 25, asset: 'assets/games/brick_breaker/music/level-25.mp3'),
  BrickBreakerMusicLevel(level: 50, asset: 'assets/games/brick_breaker/music/level-50.mp3'),
];

class BrickBreakerSoundtrackOption {
  final String id;
  final String label;
  final String? asset;

  const BrickBreakerSoundtrackOption({
    required this.id,
    required this.label,
    this.asset,
  });
}
