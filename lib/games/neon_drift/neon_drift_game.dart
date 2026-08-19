import 'dart:math' as math;
import 'dart:ui';

enum DriftPhase { ready, playing, dead }

/// A horizontal wall sliding down — slip through [gapCenter] ± gap half-width.
class DriftWall {
  double y;
  final double gapCenter;
  final double gapHalf;
  final double thickness;
  bool scored;

  DriftWall({
    required this.y,
    required this.gapCenter,
    required this.gapHalf,
    this.thickness = 14,
    this.scored = false,
  });
}

class DriftGem {
  double x;
  double y;
  bool taken;

  DriftGem({required this.x, required this.y});
}

class NeonDriftGame {
  static const playerY = 0.82;
  static const playerRadius = 14.0;
  static const spawnGap = 0.22;

  double width = 1;
  double height = 1;

  double playerX = 0.5;
  DriftPhase phase = DriftPhase.ready;
  double speed = 140;
  double elapsed = 0;
  int score = 0;
  int gems = 0;
  int highScore = 0;
  int wallsPassed = 0;

  final List<DriftWall> walls = [];
  final List<DriftGem> gemList = [];
  final math.Random _rng = math.Random();

  double _spawnTimer = 0;
  double _shake = 0;

  void resize(double w, double h) {
    width = w;
    height = h;
  }

  double get playerPx => playerX * width;
  double get playerPy => playerY * height;

  void reset({bool keepHighScore = true}) {
    final hs = keepHighScore ? highScore : 0;
    playerX = 0.5;
    phase = DriftPhase.ready;
    speed = 140;
    elapsed = 0;
    score = 0;
    gems = 0;
    wallsPassed = 0;
    walls.clear();
    gemList.clear();
    _spawnTimer = 0;
    _shake = 0;
    highScore = hs;
  }

  void start() {
    if (phase != DriftPhase.ready) return;
    phase = DriftPhase.playing;
    _spawnWall(y: -0.06);
  }

  void setPlayerX(double nx) {
    playerX = nx.clamp(0.06, 0.94);
  }

  void update(double dt) {
    if (_shake > 0) _shake = (_shake - dt * 4).clamp(0, 1);

    if (phase != DriftPhase.playing) return;

    elapsed += dt;
    speed = 140 + elapsed * 8 + wallsPassed * 2;
    _spawnTimer -= dt;

    if (_spawnTimer <= 0) {
      final topY = walls.isEmpty ? 0.0 : walls.last.y;
      if (topY > -spawnGap) {
        _spawnWall(y: topY - spawnGap - _rng.nextDouble() * 0.04);
      }
      _spawnTimer = (spawnGap * height / speed).clamp(0.35, 1.2);
    }

    for (final w in walls) {
      w.y += (speed * dt) / height;
    }

    for (final g in gemList) {
      g.y += (speed * dt) / height;
    }

    walls.removeWhere((w) => w.y > 1.15);
    gemList.removeWhere((g) => g.y > 1.1 || g.taken);

    _scorePassedWalls();
    _collectGems();
    _checkCollision();
  }

  void _spawnWall({required double y}) {
    final gapHalf = (_gapHalfForDifficulty()).clamp(0.06, 0.22);
    final gapCenter = gapHalf + _rng.nextDouble() * (1 - gapHalf * 2);
    walls.add(DriftWall(
      y: y,
      gapCenter: gapCenter,
      gapHalf: gapHalf,
    ));

    if (_rng.nextDouble() < 0.55) {
      gemList.add(DriftGem(x: gapCenter, y: y + 0.04));
    }
  }

  double _gapHalfForDifficulty() {
    return 0.20 - wallsPassed * 0.003 - elapsed * 0.002;
  }

  void _scorePassedWalls() {
    for (final w in walls) {
      if (w.scored) continue;
      if (w.y > playerY + 0.06) {
        w.scored = true;
        wallsPassed++;
        score += 10 + wallsPassed ~/ 5;
      }
    }
  }

  void _collectGems() {
    for (final g in gemList) {
      if (g.taken) continue;
      final gx = g.x * width;
      final gy = g.y * height;
      final dx = playerPx - gx;
      final dy = playerPy - gy;
      if (dx * dx + dy * dy < (playerRadius + 10) * (playerRadius + 10)) {
        g.taken = true;
        gems++;
        score += 25;
      }
    }
  }

  void _checkCollision() {
    final px = playerPx;
    final py = playerPy;
    final pr = playerRadius;

    for (final w in walls) {
      final wallTop = w.y * height;
      final wallBottom = wallTop + w.thickness;
      if (py + pr < wallTop || py - pr > wallBottom) continue;

      final gapL = (w.gapCenter - w.gapHalf) * width;
      final gapR = (w.gapCenter + w.gapHalf) * width;
      if (px - pr >= gapL && px + pr <= gapR) continue;

      _die();
      return;
    }
  }

  void _die() {
    phase = DriftPhase.dead;
    _shake = 1;
    highScore = math.max(highScore, score);
  }

  void retry() {
    final hs = highScore;
    reset(keepHighScore: true);
    highScore = hs;
    start();
  }

  Offset get shakeOffset {
    if (_shake <= 0) return Offset.zero;
    final s = _shake * 5;
    return Offset(
      math.sin(elapsed * 80) * s,
      math.cos(elapsed * 73) * s,
    );
  }
}
