import 'dart:math' as math;
import 'dart:ui';

/// One brick on the descending wall — [hp] is how many ball hits it needs.
class BreakerBrick {
  int hp;
  bool barrier;

  BreakerBrick({required this.hp, this.barrier = false});

  bool get alive => barrier || hp > 0;
}

/// Glowing pickup — hit it during a volley to fire more balls next turn.
class BallBooster {
  int row;
  int col;

  BallBooster({required this.row, required this.col});
}

class BreakerBall {
  double x;
  double y;
  double vx;
  double vy;
  bool active;
  final bool isFirst;

  BreakerBall({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    this.active = true,
    this.isFirst = false,
  });
}

enum BreakerPhase { aiming, flying, gameOver, levelClear }

/// Turn-based brick-breaker.io style: aim from the launcher ball, fire a
/// volley upward (one ball at a time), then move the launcher to where
/// the first ball landed — no breakout paddle bouncing.
class BrickBreakerGame {
  static const ballRadius = 5.0;
  static const launcherY = 0.92;
  static const dangerY = 0.82;
  static const cols = 7;
  static const rows = 8;
  static const brickW = 1 / cols;
  static const brickH = 0.045;
  static const speed = 420.0;
  static const fireGap = 0.07;

  double width = 1;
  double height = 1;

  double launcherX = 0.5;
  double aimAngle = -math.pi / 2;
  int score = 0;
  int highScore = 0;
  int level = 1;
  int ballsPerShot = 1;
  int step = 0;
  BreakerPhase phase = BreakerPhase.aiming;

  final List<BreakerBall> balls = [];
  final List<List<BreakerBrick?>> grid = [];
  final List<BallBooster> boosters = [];

  int _ballsLeftToFire = 0;
  double _fireCooldown = 0;
  double? _firstBallLandX;

  final math.Random _rng = math.Random();

  void resize(double w, double h) {
    width = w;
    height = h;
  }

  double get launcherPx => launcherX * width;
  double get launcherPy => launcherY * height;

  void reset({bool keepHighScore = true}) {
    final hs = keepHighScore ? highScore : 0;
    score = 0;
    level = 1;
    ballsPerShot = 1;
    step = 0;
    phase = BreakerPhase.aiming;
    launcherX = 0.5;
    aimAngle = -math.pi / 2;
    balls.clear();
    grid.clear();
    boosters.clear();
    _ballsLeftToFire = 0;
    _fireCooldown = 0;
    _firstBallLandX = null;
    highScore = hs;
    _spawnLevel();
  }

  void _spawnLevel() {
    grid.clear();
    boosters.clear();
    for (var r = 0; r < rows; r++) {
      final row = <BreakerBrick?>[];
      for (var c = 0; c < cols; c++) {
        if (_rng.nextDouble() < 0.12) {
          row.add(null);
          continue;
        }
        if (level > 2 && _rng.nextDouble() < 0.06) {
          row.add(BreakerBrick(hp: 0, barrier: true));
          continue;
        }
        final maxHp = (level + _rng.nextInt(4)).clamp(1, 12);
        row.add(BreakerBrick(hp: maxHp));
      }
      grid.add(row);
    }
    _seedBoosters(spawnAllRows: true);
    phase = BreakerPhase.aiming;
  }

  void _seedBoosters({required bool spawnAllRows, int rowOnly = 0}) {
    final start = spawnAllRows ? 0 : rowOnly;
    final end = spawnAllRows ? rows : rowOnly + 1;
    for (var r = start; r < end; r++) {
      for (var c = 0; c < cols; c++) {
        if (grid[r][c] != null) continue;
        if (_hasBoosterAt(r, c)) continue;
        if (_rng.nextDouble() < 0.11) {
          boosters.add(BallBooster(row: r, col: c));
        }
      }
    }
  }

  bool _hasBoosterAt(int row, int col) {
    for (final b in boosters) {
      if (b.row == row && b.col == col) return true;
    }
    return false;
  }

  ({double left, double top, double right, double bottom}) cellRect(int r, int c) {
    final left = c * brickW * width + 2;
    final top = r * brickH * height + 8;
    return (
      left: left,
      top: top,
      right: left + brickW * width - 4,
      bottom: top + brickH * height - 4,
    );
  }

  /// Aim from the launcher ball toward the finger — launcher stays put.
  void setAimFromTouch(double nx, double ny) {
    if (phase != BreakerPhase.aiming) return;
    final dx = nx * width - launcherPx;
    final dy = ny * height - launcherPy;
    if (dy >= -6) return;
    aimAngle = math.atan2(dy, dx).clamp(-math.pi * 0.92, -math.pi * 0.08);
  }

  void shoot() {
    if (phase != BreakerPhase.aiming) return;
    balls.clear();
    _firstBallLandX = null;
    _ballsLeftToFire = ballsPerShot;
    _fireCooldown = 0;
    phase = BreakerPhase.flying;
  }

  void _spawnNextBall() {
    final isFirst = balls.isEmpty;
    balls.add(BreakerBall(
      x: launcherPx,
      y: launcherPy,
      vx: math.cos(aimAngle) * speed,
      vy: math.sin(aimAngle) * speed,
      isFirst: isFirst,
    ));
  }

  void update(double dt) {
    if (phase == BreakerPhase.gameOver || phase == BreakerPhase.aiming) return;

    if (_ballsLeftToFire > 0) {
      _fireCooldown -= dt;
      if (_fireCooldown <= 0) {
        _spawnNextBall();
        _ballsLeftToFire--;
        _fireCooldown = fireGap;
      }
    }

    var anyActive = false;
    for (final b in balls) {
      if (!b.active) continue;
      anyActive = true;
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      _bounceOffWalls(b);

      _hitBricks(b);
      _hitBoosters(b);

      final floor = launcherY * height;
      if (b.y >= floor) {
        if (b.isFirst && _firstBallLandX == null) {
          _firstBallLandX = b.x.clamp(ballRadius, width - ballRadius);
        }
        b.active = false;
        b.y = floor;
        b.vx = 0;
        b.vy = 0;
      }
    }

    if (_ballsLeftToFire == 0 && !anyActive) {
      _endVolley();
    }
  }

  void _hitBricks(BreakerBall b) {
    for (var r = 0; r < grid.length; r++) {
      for (var c = 0; c < grid[r].length; c++) {
        final brick = grid[r][c];
        if (brick == null || !brick.alive) continue;

        final left = c * brickW * width;
        final top = r * brickH * height + 8;
        final right = left + brickW * width - 4;
        final bottom = top + brickH * height - 4;

        if (b.x + ballRadius < left ||
            b.x - ballRadius > right ||
            b.y + ballRadius < top ||
            b.y - ballRadius > bottom) {
          continue;
        }

        if (brick.barrier) {
          _reflectFromRect(b, left, top, right, bottom);
          return;
        }

        brick.hp--;
        score += 10;
        if (brick.hp <= 0) {
          grid[r][c] = null;
          score += 5;
        }
        _reflectFromRect(b, left, top, right, bottom);
        return;
      }
    }
  }

  void _hitBoosters(BreakerBall b) {
    for (var i = boosters.length - 1; i >= 0; i--) {
      final pick = boosters[i];
      final rect = cellRect(pick.row, pick.col);
      final cx = (rect.left + rect.right) / 2;
      final cy = (rect.top + rect.bottom) / 2;
      final dx = b.x - cx;
      final dy = b.y - cy;
      if (dx * dx + dy * dy > (ballRadius + 10) * (ballRadius + 10)) continue;

      boosters.removeAt(i);
      ballsPerShot = (ballsPerShot + 1).clamp(1, 12);
      score += 20;
      return;
    }
  }

  void _reflectFromRect(
    BreakerBall b,
    double left,
    double top,
    double right,
    double bottom,
  ) {
    final cx = (left + right) / 2;
    final cy = (top + bottom) / 2;
    final dx = b.x - cx;
    final dy = b.y - cy;
    if (dx.abs() / (right - left) > dy.abs() / (bottom - top)) {
      b.vx = dx > 0 ? b.vx.abs() : -b.vx.abs();
    } else {
      b.vy = dy > 0 ? b.vy.abs() : -b.vy.abs();
    }
  }

  void _endVolley() {
    step++;

    if (_firstBallLandX != null) {
      launcherX = (_firstBallLandX! / width).clamp(0.08, 0.92);
    }

    for (var r = grid.length - 1; r >= 0; r--) {
      for (var c = 0; c < grid[r].length; c++) {
        final brick = grid[r][c];
        if (brick == null || !brick.alive) continue;
        final y = (r + 1) * brickH * height + 8;
        if (y >= dangerY * height) {
          phase = BreakerPhase.gameOver;
          highScore = math.max(highScore, score);
          return;
        }
      }
    }

    for (var r = grid.length - 1; r > 0; r--) {
      for (var c = 0; c < cols; c++) {
        grid[r][c] = grid[r - 1][c];
      }
    }
    for (final pick in boosters) {
      pick.row++;
    }
    boosters.removeWhere((p) => p.row >= rows);

    for (var c = 0; c < cols; c++) {
      if (_rng.nextDouble() < 0.15) {
        grid[0][c] = null;
      } else {
        grid[0][c] = BreakerBrick(hp: (level + _rng.nextInt(3)).clamp(1, 10));
      }
    }
    _seedBoosters(spawnAllRows: false, rowOnly: 0);

    if (_allClear()) {
      level++;
      score += 100 * level;
      _spawnLevel();
      phase = BreakerPhase.levelClear;
      return;
    }

    balls.clear();
    phase = BreakerPhase.aiming;
  }

  bool _allClear() {
    for (final row in grid) {
      for (final b in row) {
        if (b != null && b.alive && !b.barrier) return false;
      }
    }
    return true;
  }

  void acknowledgeLevelClear() {
    if (phase == BreakerPhase.levelClear) {
      phase = BreakerPhase.aiming;
    }
  }

  void _bounceOffWalls(BreakerBall b) {
    if (b.x < ballRadius) {
      b.x = ballRadius;
      b.vx = b.vx.abs();
    } else if (b.x > width - ballRadius) {
      b.x = width - ballRadius;
      b.vx = -b.vx.abs();
    }
    if (b.y < ballRadius) {
      b.y = ballRadius;
      b.vy = b.vy.abs();
    }
  }

  /// Dotted aim preview — mirrors in-flight wall bounces (left, right, ceiling).
  ({List<Offset> dots, List<Offset> bounces}) aimPreview() {
    if (width <= 1 || height <= 1) {
      return (dots: const [], bounces: const []);
    }

    final dots = <Offset>[];
    final bounces = <Offset>[];
    var x = launcherPx;
    var y = launcherPy;
    var dx = math.cos(aimAngle);
    var dy = math.sin(aimAngle);
    const stepLen = 5.0;
    const maxSteps = 320;
    final floor = launcherY * height;

    for (var i = 0; i < maxSteps; i++) {
      x += dx * stepLen;
      y += dy * stepLen;

      var bounced = false;
      if (x < ballRadius) {
        x = ballRadius + (ballRadius - x);
        dx = dx.abs();
        bounced = true;
      } else if (x > width - ballRadius) {
        x = (width - ballRadius) - (x - (width - ballRadius));
        dx = -dx.abs();
        bounced = true;
      }
      if (y < ballRadius) {
        y = ballRadius + (ballRadius - y);
        dy = dy.abs();
        bounced = true;
      }
      if (y >= floor) break;

      if (bounced) {
        bounces.add(Offset(x, y));
        if (bounces.length > 12) break;
      } else if (i % 3 == 0) {
        dots.add(Offset(x, y));
      }
    }
    return (dots: dots, bounces: bounces);
  }
}
