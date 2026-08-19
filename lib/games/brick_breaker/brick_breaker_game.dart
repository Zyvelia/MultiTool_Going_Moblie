import 'dart:math' as math;

/// One brick on the descending wall — [hp] is how many ball hits it needs.
class BreakerBrick {
  int hp;
  bool barrier;

  BreakerBrick({required this.hp, this.barrier = false});

  bool get alive => barrier || hp > 0;
}

class BreakerBall {
  double x;
  double y;
  double vx;
  double vy;
  bool active;

  BreakerBall({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    this.active = true,
  });
}

enum BreakerPhase { aiming, flying, settling, gameOver, levelClear }

/// Core rules mirror brick-breaker.io: shoot up from the paddle, bricks
/// carry HP numbers, and the wall drops a row after each volley.
class BrickBreakerGame {
  static const ballRadius = 5.0;
  static const paddleW = 72.0;
  static const paddleH = 10.0;
  static const paddleY = 0.92;
  static const dangerY = 0.82;
  static const cols = 7;
  static const rows = 8;
  static const brickW = 1 / cols;
  static const brickH = 0.045;
  static const speed = 420.0;

  double width = 1;
  double height = 1;

  double paddleX = 0.5;
  double aimAngle = -math.pi / 2;
  int score = 0;
  int highScore = 0;
  int level = 1;
  int ballsPerShot = 1;
  BreakerPhase phase = BreakerPhase.aiming;

  final List<BreakerBall> balls = [];
  final List<List<BreakerBrick?>> grid = [];

  final math.Random _rng = math.Random();

  void resize(double w, double h) {
    width = w;
    height = h;
  }

  void reset({bool keepHighScore = true}) {
    final hs = keepHighScore ? highScore : 0;
    score = 0;
    level = 1;
    ballsPerShot = 1;
    phase = BreakerPhase.aiming;
    paddleX = 0.5;
    aimAngle = -math.pi / 2;
    balls.clear();
    grid.clear();
    highScore = hs;
    _spawnLevel();
  }

  void _spawnLevel() {
    grid.clear();
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
    phase = BreakerPhase.aiming;
  }

  void setAimFromTouch(double nx, double ny) {
    if (phase != BreakerPhase.aiming) return;
    final px = paddleX * width;
    final py = paddleY * height;
    final dx = nx * width - px;
    final dy = ny * height - py;
    if (dy >= -8) return; // must aim upward
    aimAngle = math.atan2(dy, dx).clamp(-math.pi * 0.92, -math.pi * 0.08);
  }

  void movePaddle(double nx) {
    if (phase == BreakerPhase.gameOver) return;
    paddleX = nx.clamp(paddleW / width / 2, 1 - paddleW / width / 2);
  }

  void shoot() {
    if (phase != BreakerPhase.aiming) return;
    balls.clear();
    final px = paddleX * width;
    final py = paddleY * height;
    final spread = ballsPerShot > 1 ? 0.06 : 0.0;
    for (var i = 0; i < ballsPerShot; i++) {
      final t = ballsPerShot == 1
          ? 0.0
          : (i / (ballsPerShot - 1) - 0.5) * 2 * spread;
      final a = aimAngle + t;
      balls.add(BreakerBall(
        x: px,
        y: py - paddleH,
        vx: math.cos(a) * speed,
        vy: math.sin(a) * speed,
      ));
    }
    phase = BreakerPhase.flying;
  }

  void update(double dt) {
    if (phase == BreakerPhase.gameOver || phase == BreakerPhase.aiming) return;

    var anyActive = false;
    for (final b in balls) {
      if (!b.active) continue;
      anyActive = true;
      b.x += b.vx * dt;
      b.y += b.vy * dt;

      // Side walls
      if (b.x < ballRadius) {
        b.x = ballRadius;
        b.vx = b.vx.abs();
      } else if (b.x > width - ballRadius) {
        b.x = width - ballRadius;
        b.vx = -b.vx.abs();
      }

      // Ceiling
      if (b.y < ballRadius) {
        b.y = ballRadius;
        b.vy = b.vy.abs();
      }

      // Bricks
      _hitBricks(b);

      // Settled at the bottom
      final floor = paddleY * height - paddleH;
      if (b.y >= floor) {
        b.active = false;
        b.y = floor;
        b.vx = 0;
        b.vy = 0;
      }
    }

    if (phase == BreakerPhase.flying && !anyActive) {
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
          _bounceFromRect(b, left, top, right, bottom);
          continue;
        }

        brick.hp--;
        score += 10;
        if (brick.hp <= 0) {
          grid[r][c] = null;
          score += 5;
          if (_rng.nextDouble() < 0.08) {
            ballsPerShot = (ballsPerShot + 1).clamp(1, 8);
          }
        }
        _bounceFromRect(b, left, top, right, bottom);
        return;
      }
    }
  }

  void _bounceFromRect(
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
    // Drop every brick one row; game over if any crosses the danger line.
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

    // Shift down
    for (var r = grid.length - 1; r > 0; r--) {
      for (var c = 0; c < cols; c++) {
        grid[r][c] = grid[r - 1][c];
      }
    }
    for (var c = 0; c < cols; c++) {
      if (_rng.nextDouble() < 0.15) {
        grid[0][c] = null;
      } else {
        grid[0][c] = BreakerBrick(hp: (level + _rng.nextInt(3)).clamp(1, 10));
      }
    }

    if (_allClear()) {
      level++;
      score += 100 * level;
      ballsPerShot = (ballsPerShot + 1).clamp(1, 8);
      _spawnLevel();
      phase = BreakerPhase.levelClear;
      return;
    }

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
}
