import 'dart:math' as math;
import 'dart:ui';

enum BrickKind { normal, heavy, barrier }

enum LaserKind { vertical, horizontal, cross }

enum LaserBeamShape { vertical, horizontal, cross }

/// Buried laser pickup — mine it, then it fires immediately on unlock.
class MapLaser {
  int row;
  int col;
  LaserKind kind;
  int mineHp;
  final int mineMax;

  MapLaser({
    required this.row,
    required this.col,
    required this.kind,
    required this.mineHp,
  }) : mineMax = mineHp;

  final Map<int, double> _nextHitFromBall = {};
  static const hitGap = 0.07;

  bool tryChargeFrom(BreakerBall ball, double volleyTime) {
    final next = _nextHitFromBall[ball.id] ?? 0;
    if (volleyTime < next) return false;
    _nextHitFromBall[ball.id] = volleyTime + hitGap;
    return true;
  }
}

/// Glowing +ball orb on empty cells — fly through to add a permanent ball.
class BallBooster {
  int row;
  int col;

  BallBooster({required this.row, required this.col});
}

class BreakerBrick {
  int hp;
  BrickKind kind;

  BreakerBrick({required this.hp, this.kind = BrickKind.normal});

  bool get alive => kind == BrickKind.barrier || hp > 0;
}

class LaserBeam {
  final int row;
  final int col;
  final LaserBeamShape shape;
  double life;

  LaserBeam({
    required this.row,
    required this.col,
    required this.shape,
    this.life = 0.35,
  });
}

class BreakerBall {
  double x;
  double y;
  double vx;
  double vy;
  bool active;
  final bool isFirst;
  final int id;

  static int _nextId = 0;

  BreakerBall({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    this.active = true,
    this.isFirst = false,
  }) : id = _nextId++;
}

enum BreakerPhase { aiming, flying, gameOver, levelClear }

class BrickBreakerGame {
  static const ballRadius = 5.0;
  static const launcherY = 0.92;
  static const dangerY = 0.82;
  static const gridTopY = 0.03;
  static const cols = 7;
  static const rows = 12;
  static const brickW = 1 / cols;
  /// Rows span from [gridTopY] down to [dangerY] — no invisible floor where bricks vanish.
  static const brickH = (dangerY - gridTopY) / rows;
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
  final List<MapLaser> lasers = [];
  final List<BallBooster> ballBoosters = [];
  final List<LaserBeam> laserBeams = [];

  int _ballsLeftToFire = 0;
  double _fireCooldown = 0;
  double _volleyTime = 0;
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
    lasers.clear();
    ballBoosters.clear();
    laserBeams.clear();
    _ballsLeftToFire = 0;
    _fireCooldown = 0;
    _firstBallLandX = null;
    highScore = hs;
    _initEmptyGrid();
    _spawnStarterBrick();
    phase = BreakerPhase.aiming;
  }

  void _initEmptyGrid() {
    grid.clear();
    for (var r = 0; r < rows; r++) {
      grid.add(List<BreakerBrick?>.filled(cols, null));
    }
  }

  void _spawnStarterBrick() {
    final col = _rng.nextInt(cols);
    grid[0][col] = _makeBrick(step: 0);
    _seedBallBoosters(rowOnly: 0, extraChance: 0.35);
  }

  void _spawnLevel() {
    _initEmptyGrid();
    lasers.clear();
    ballBoosters.clear();
    laserBeams.clear();
    final count = (2 + level).clamp(1, cols);
    final used = <int>{};
    while (used.length < count) {
      used.add(_rng.nextInt(cols));
    }
    for (final c in used) {
      grid[0][c] = _makeBrick(step: step + level * 3);
    }
    _seedBuriedLasers(rowOnly: 0);
    _seedBallBoosters(rowOnly: 0);
    phase = BreakerPhase.aiming;
  }

  int _bricksForStep(int s) {
    if (s <= 0) return 1;
    if (s < 4) return 1 + _rng.nextInt(2);
    if (s < 10) return 2 + _rng.nextInt(2);
    if (s < 20) return 2 + _rng.nextInt(3);
    if (s < 35) return 3 + _rng.nextInt(3);
    return 4 + _rng.nextInt(4);
  }

  BreakerBrick _makeBrick({required int step}) {
    final roll = _rng.nextDouble();
    if (step >= 8 && roll < 0.05) {
      return BreakerBrick(hp: 0, kind: BrickKind.barrier);
    }
    if (step >= 2 && roll < 0.35) {
      final hp = (2 + _rng.nextInt(3) + step ~/ 8).clamp(2, 18);
      return BreakerBrick(hp: hp, kind: BrickKind.heavy);
    }
    final hp = (1 + _rng.nextInt(2) + step ~/ 10 + level).clamp(1, 15);
    return BreakerBrick(hp: hp, kind: BrickKind.normal);
  }

  void _spawnTopRow() {
    final count = _bricksForStep(step).clamp(1, cols);
    final slots = List.generate(cols, (i) => i)..shuffle(_rng);
    for (var i = 0; i < count; i++) {
      grid[0][slots[i]] = _makeBrick(step: step);
    }
    _seedBuriedLasers(rowOnly: 0);
    _seedBallBoosters(rowOnly: 0);
  }

  void _seedBallBoosters({required int rowOnly, double extraChance = 0}) {
    for (var c = 0; c < cols; c++) {
      if (grid[rowOnly][c] != null) continue;
      if (_laserAt(rowOnly, c) != null) continue;
      if (_boosterAt(rowOnly, c) != null) continue;
      final chance = extraChance > 0 ? extraChance : (0.16 + step * 0.005);
      if (_rng.nextDouble() > chance) continue;
      ballBoosters.add(BallBooster(row: rowOnly, col: c));
    }
  }

  BallBooster? _boosterAt(int row, int col) {
    for (final b in ballBoosters) {
      if (b.row == row && b.col == col) return b;
    }
    return null;
  }

  LaserKind _randomLaserKind() {
    final roll = _rng.nextDouble();
    if (roll < 0.34) return LaserKind.vertical;
    if (roll < 0.67) return LaserKind.horizontal;
    return LaserKind.cross;
  }

  void _seedBuriedLasers({required int rowOnly}) {
    if (step < 2) return;
    final chance = 0.10 + step * 0.002;
    for (var c = 0; c < cols; c++) {
      if (grid[rowOnly][c] != null) continue;
      if (_laserAt(rowOnly, c) != null) continue;
      if (_rng.nextDouble() > chance) continue;
      lasers.add(MapLaser(
        row: rowOnly,
        col: c,
        kind: _randomLaserKind(),
        mineHp: 2 + _rng.nextInt(3),
      ));
    }
  }

  MapLaser? _laserAt(int row, int col) {
    for (final p in lasers) {
      if (p.row == row && p.col == col) return p;
    }
    return null;
  }

  double rowTopPx(int r) => (gridTopY + r * brickH) * height;
  double rowBottomPx(int r) => (gridTopY + (r + 1) * brickH) * height;

  ({double left, double top, double right, double bottom}) cellRect(int r, int c) {
    final left = c * brickW * width + 2;
    final top = rowTopPx(r) + 2;
    return (
      left: left,
      top: top,
      right: left + brickW * width - 4,
      bottom: rowBottomPx(r) - 2,
    );
  }

  double rowCenterY(int r) => (rowTopPx(r) + rowBottomPx(r)) / 2;

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
    _volleyTime = 0;
    phase = BreakerPhase.flying;
  }

  /// Stop the volley early — drops every ball to the floor and ends the turn.
  void dropAllBalls() {
    if (phase != BreakerPhase.flying) return;

    _ballsLeftToFire = 0;
    final floor = launcherY * height;

    for (final b in balls) {
      if (!b.active) continue;
      if (b.isFirst && _firstBallLandX == null) {
        _firstBallLandX = b.x.clamp(ballRadius, width - ballRadius);
      }
      b.active = false;
      b.y = floor;
      b.vx = 0;
      b.vy = 0;
    }

    _endVolley();
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
    for (var i = laserBeams.length - 1; i >= 0; i--) {
      laserBeams[i].life -= dt;
      if (laserBeams[i].life <= 0) laserBeams.removeAt(i);
    }

    if (phase == BreakerPhase.gameOver || phase == BreakerPhase.aiming) return;

    _volleyTime += dt;

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
      _hitLasers(b);
      _hitBallBoosters(b);

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
        final top = rowTopPx(r);
        final right = left + brickW * width - 4;
        final bottom = rowBottomPx(r) - 4;

        if (b.x + ballRadius < left ||
            b.x - ballRadius > right ||
            b.y + ballRadius < top ||
            b.y - ballRadius > bottom) {
          continue;
        }

        if (brick.kind == BrickKind.barrier) {
          _reflectFromRect(b, left, top, right, bottom);
          return;
        }

        _damageBrick(r, c, 1);
        _reflectFromRect(b, left, top, right, bottom);
        return;
      }
    }
  }

  void _hitLasers(BreakerBall b) {
    final unlocked = <MapLaser>[];

    for (final p in lasers) {
      final rect = cellRect(p.row, p.col);
      if (b.x + ballRadius < rect.left ||
          b.x - ballRadius > rect.right ||
          b.y + ballRadius < rect.top ||
          b.y - ballRadius > rect.bottom) {
        continue;
      }

      if (!p.tryChargeFrom(b, _volleyTime)) continue;

      p.mineHp--;
      score += 5;
      if (p.mineHp <= 0) {
        unlocked.add(p);
        score += 25;
      }
    }

    for (final p in unlocked) {
      _fireLaser(p);
      lasers.remove(p);
    }
  }

  void _hitBallBoosters(BreakerBall b) {
    for (var i = ballBoosters.length - 1; i >= 0; i--) {
      final pick = ballBoosters[i];
      final rect = cellRect(pick.row, pick.col);
      if (b.x + ballRadius < rect.left ||
          b.x - ballRadius > rect.right ||
          b.y + ballRadius < rect.top ||
          b.y - ballRadius > rect.bottom) {
        continue;
      }

      ballBoosters.removeAt(i);
      ballsPerShot = (ballsPerShot + 1).clamp(1, 24);
      score += 30;
    }
  }

  void _damageBrick(int r, int c, int amount, {bool fromLaser = false}) {
    final brick = grid[r][c];
    if (brick == null || !brick.alive) return;
    if (brick.kind == BrickKind.barrier) return;

    brick.hp -= amount;
    score += 10;

    if (brick.hp <= 0) {
      grid[r][c] = null;
      score += 5;
    }
  }

  void _fireLaser(MapLaser laser) {
    switch (laser.kind) {
      case LaserKind.vertical:
        _fireLaserVertical(laser.row, laser.col);
      case LaserKind.horizontal:
        _fireLaserHorizontal(laser.row, laser.col);
      case LaserKind.cross:
        _fireLaserCross(laser.row, laser.col);
    }
    score += 15;
  }

  void _fireLaserVertical(int row, int col) {
    laserBeams.add(LaserBeam(row: row, col: col, shape: LaserBeamShape.vertical));
    for (var r = 0; r <= row; r++) {
      _damageBrick(r, col, 1, fromLaser: true);
    }
  }

  void _fireLaserHorizontal(int row, int col) {
    laserBeams.add(LaserBeam(row: row, col: col, shape: LaserBeamShape.horizontal));
    for (var c = 0; c < cols; c++) {
      _damageBrick(row, c, 1, fromLaser: true);
    }
  }

  void _fireLaserCross(int row, int col) {
    laserBeams.add(LaserBeam(row: row, col: col, shape: LaserBeamShape.cross));
    for (var c = 0; c < cols; c++) {
      _damageBrick(row, c, 1, fromLaser: true);
    }
    for (var r = 0; r < rows; r++) {
      _damageBrick(r, col, 1, fromLaser: true);
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
    level++;

    if (_firstBallLandX != null) {
      launcherX = (_firstBallLandX! / width).clamp(0.08, 0.92);
    }

    _checkGameOver();
    if (phase == BreakerPhase.gameOver) return;

    _shiftWallDown();
    _spawnTopRow();
    _checkGameOver();
    if (phase == BreakerPhase.gameOver) return;

    if (_allClear()) {
      score += 100 * level;
      _spawnLevel();
      phase = BreakerPhase.levelClear;
      return;
    }

    balls.clear();
    phase = BreakerPhase.aiming;
  }

  bool _countsTowardLoss(BreakerBrick? brick) =>
      brick != null && brick.alive && brick.kind != BrickKind.barrier;

  void _checkGameOver() {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final brick = grid[r][c];
        if (!_countsTowardLoss(brick)) continue;
        if (rowBottomPx(r) >= dangerY * height) {
          phase = BreakerPhase.gameOver;
          highScore = math.max(highScore, score);
          return;
        }
      }
    }
  }

  void _shiftWallDown() {
    // Bottom row is the danger line — destructible bricks here end the run on the next push.
    for (var c = 0; c < cols; c++) {
      if (_countsTowardLoss(grid[rows - 1][c])) {
        phase = BreakerPhase.gameOver;
        highScore = math.max(highScore, score);
        return;
      }
    }

    for (var r = rows - 1; r > 0; r--) {
      for (var c = 0; c < cols; c++) {
        grid[r][c] = grid[r - 1][c];
      }
    }
    for (var c = 0; c < cols; c++) {
      grid[0][c] = null;
    }
    for (final p in lasers) {
      p.row++;
    }
    lasers.removeWhere((p) => p.row >= rows);
    for (final pick in ballBoosters) {
      pick.row++;
    }
    ballBoosters.removeWhere((p) => p.row >= rows);
  }

  bool _allClear() {
    for (final row in grid) {
      for (final b in row) {
        if (b != null && b.alive && b.kind != BrickKind.barrier) return false;
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
