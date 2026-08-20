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

const brickBreakerExtraMusic = <({String id, String label, String asset})>[
  (
    id: 'assets/games/brick_breaker/music/volo-theme.mp3',
    label: 'Volo Theme (Piano Etude)',
    asset: 'assets/games/brick_breaker/music/volo-theme.mp3',
  ),
  (
    id: 'assets/games/brick_breaker/music/cynthia-battle.mp3',
    label: 'Champion Cynthia Battle',
    asset: 'assets/games/brick_breaker/music/cynthia-battle.mp3',
  ),
  (
    id: 'assets/games/brick_breaker/music/cynthia-approach.mp3',
    label: 'Approaching Champion Cynthia',
    asset: 'assets/games/brick_breaker/music/cynthia-approach.mp3',
  ),
];

/// All bundled tracks — used by Random soundtrack mode.
const brickBreakerMusicPool = <String>[
  brickBreakerDefaultMusic,
  'assets/games/brick_breaker/music/level-10.mp3',
  'assets/games/brick_breaker/music/level-25.mp3',
  'assets/games/brick_breaker/music/level-50.mp3',
  ...brickBreakerExtraMusic.map((t) => t.asset),
];

const brickBreakerWarnSound = 'assets/games/brick_breaker/sfx/low-health.mp3';
const brickBreakerWarnVolume = 0.32;

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
