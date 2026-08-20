import 'dart:async';
import 'dart:math' as math;

import 'brick_breaker_awards.dart';
import 'brick_breaker_save.dart';
import 'brick_breaker_gameplay_settings.dart';
import 'brick_breaker_mode.dart';
import 'brick_breaker_shapes.dart';
import 'dart:ui';

enum BrickKind { normal, heavy, barrier }

enum LaserKind { vertical, horizontal, cross }

enum LaserBeamShape { vertical, horizontal, cross }

/// Buried laser pickup — mine it, then each ball that passes through fires it until the wave ends.
class MapLaser {
  int row;
  int col;
  LaserKind kind;
  int mineHp;
  final int mineMax;
  bool armed = false;
  bool readyForWave = false;
  int waveHits = 0;

  MapLaser({
    required this.row,
    required this.col,
    required this.kind,
    required this.mineHp,
    int? mineMax,
  }) : mineMax = mineMax ?? mineHp;

  bool get buried => !armed;

  final Map<int, double> _nextHitFromBall = {};
  static const hitGap = 0.07;

  bool tryChargeFrom(BreakerBall ball, double volleyTime) {
    final next = _nextHitFromBall[ball.id] ?? 0;
    if (volleyTime < next) return false;
    _nextHitFromBall[ball.id] = volleyTime + hitGap;
    return true;
  }

  void resetVolleyCooldowns() {
    _nextHitFromBall.clear();
  }
}

/// Glowing +ball orb on empty cells — fly through to add permanent balls.
class BallBooster {
  int row;
  int col;
  final int bonus;

  BallBooster({required this.row, required this.col, this.bonus = 1});
}

class BreakerBrick {
  int hp;
  BrickKind kind;
  final double angle;
  final BrickShape shape;

  BreakerBrick({
    required this.hp,
    this.kind = BrickKind.normal,
    required this.angle,
    this.shape = BrickShape.round,
  });

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
  static const ballSepSlop = 0.85;
  static const ballMaxCollideIters = 4;
  static const ballSubstepDist = ballRadius * 0.75;

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
  BrickBreakerMode mode = BrickBreakerMode.endless;
  double gridDriftY = 0;
  double gridDriftX = 0;
  double _siegeTime = 0;
  bool dangerWarning = false;
  int _lastWarnMs = 0;

  final List<BreakerBall> balls = [];
  final List<List<BreakerBrick?>> grid = [];
  final List<MapLaser> lasers = [];
  final List<BallBooster> ballBoosters = [];
  final List<LaserBeam> laserBeams = [];

  int _ballsLeftToFire = 0;
  double _fireCooldown = 0;
  double _volleyTime = 0;
  double? _firstBallLandX;
  double _sessionTime = 0;
  double _lastBallSpeedMul = 1;

  final math.Random _rng = math.Random();

  void Function(String name)? onSfx;
  void Function(int score)? onFullClear;
  BrickBreakerGameplaySettings? gameplaySettings;

  BrickBreakerScoreAward? lastClearAward;
  BrickBreakerScoreAward? lastScoreAward;

  void _sfx(String name) => onSfx?.call(name);

  void resize(double w, double h) {
    width = w;
    height = h;
  }

  double get launcherPx => launcherX * width;
  double get launcherPy => launcherY * height;

  Future<void> configureMode(BrickBreakerMode gameMode, {required int storedHighScore}) async {
    mode = gameMode;
    highScore = storedHighScore;
    if (await BrickBreakerSave.tryRestore(gameMode, this)) {
      dangerWarning = false;
      return;
    }
    gridDriftY = 0;
    gridDriftX = 0;
    _siegeTime = 0;
    reset(keepHighScore: true);
  }

  void reset({bool keepHighScore = true}) {
    unawaited(BrickBreakerSave.clear(mode));
    _sfx('stopDangerWarn');
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
    lastClearAward = null;
    lastScoreAward = null;
    gridDriftY = 0;
    gridDriftX = 0;
    _siegeTime = 0;
    dangerWarning = false;
    highScore = hs;
    _sessionTime = 0;
    _lastBallSpeedMul = 1;
    _initEmptyGrid();
    _spawnStarterBrick();
    phase = BreakerPhase.aiming;
  }

  Map<String, dynamic> toProgressJson() {
    return {
      'v': BrickBreakerSave.version,
      'level': level,
      'step': step,
      'score': score,
      'ballsPerShot': ballsPerShot,
      'launcherX': launcherX,
      'aimAngle': aimAngle,
      'phase': phase == BreakerPhase.flying ? BreakerPhase.aiming.index : phase.index,
      'grid': grid
          .map(
            (row) => row
                .map(
                  (b) => b == null
                      ? null
                      : {
                          'hp': b.hp,
                          'kind': b.kind.index,
                          'angle': b.angle,
                          'shape': b.shape.index,
                        },
                )
                .toList(),
          )
          .toList(),
      'lasers': lasers
          .map(
            (l) => {
              'row': l.row,
              'col': l.col,
              'kind': l.kind.index,
              'mineHp': l.mineHp,
              'mineMax': l.mineMax,
              'armed': l.armed,
              'ready': l.readyForWave,
              'waveHits': l.waveHits,
            },
          )
          .toList(),
      'boosters': ballBoosters
          .map((b) => {'row': b.row, 'col': b.col, 'bonus': b.bonus})
          .toList(),
      'gridDriftY': gridDriftY,
      'gridDriftX': gridDriftX,
      'siegeTime': _siegeTime,
      'sessionTime': _sessionTime,
    };
  }

  bool restoreFromProgress(Map<String, dynamic> data) {
    if (data['v'] != BrickBreakerSave.version) return false;
    final phaseIndex = data['phase'] as int? ?? BreakerPhase.aiming.index;
    if (phaseIndex == BreakerPhase.gameOver.index) return false;

    level = data['level'] as int? ?? 1;
    step = data['step'] as int? ?? 0;
    score = data['score'] as int? ?? 0;
    ballsPerShot = data['ballsPerShot'] as int? ?? 1;
    launcherX = (data['launcherX'] as num?)?.toDouble() ?? 0.5;
    aimAngle = (data['aimAngle'] as num?)?.toDouble() ?? -math.pi / 2;
    gridDriftY = (data['gridDriftY'] as num?)?.toDouble() ?? 0;
    gridDriftX = (data['gridDriftX'] as num?)?.toDouble() ?? 0;
    _siegeTime = (data['siegeTime'] as num?)?.toDouble() ?? 0;
    _sessionTime = (data['sessionTime'] as num?)?.toDouble() ?? 0;

    balls.clear();
    laserBeams.clear();
    _ballsLeftToFire = 0;
    _fireCooldown = 0;
    _firstBallLandX = null;
    dangerWarning = false;
    phase = phaseIndex == BreakerPhase.flying.index
        ? BreakerPhase.aiming
        : BreakerPhase.values[phaseIndex.clamp(0, BreakerPhase.values.length - 1)];

    grid.clear();
    final rawGrid = data['grid'] as List<dynamic>? ?? [];
    for (var r = 0; r < rows; r++) {
      final row = <BreakerBrick?>[];
      final rawRow = r < rawGrid.length ? rawGrid[r] as List<dynamic>? : null;
      for (var c = 0; c < cols; c++) {
        final rawBrick = rawRow != null && c < rawRow.length ? rawRow[c] : null;
        if (rawBrick is! Map<String, dynamic>) {
          row.add(null);
          continue;
        }
        row.add(
          BreakerBrick(
            hp: rawBrick['hp'] as int? ?? 1,
            kind: BrickKind.values[
                (rawBrick['kind'] as int? ?? 0).clamp(0, BrickKind.values.length - 1)],
            angle: (rawBrick['angle'] as num?)?.toDouble() ?? 0,
            shape: BrickShape.values[
                (rawBrick['shape'] as int? ?? 0).clamp(0, BrickShape.values.length - 1)],
          ),
        );
      }
      grid.add(row);
    }

    lasers.clear();
    for (final raw in data['lasers'] as List<dynamic>? ?? []) {
      if (raw is! Map<String, dynamic>) continue;
      final mineHp = raw['mineHp'] as int? ?? 1;
      lasers.add(
        MapLaser(
          row: raw['row'] as int? ?? 0,
          col: raw['col'] as int? ?? 0,
          kind: LaserKind.values[
              (raw['kind'] as int? ?? 0).clamp(0, LaserKind.values.length - 1)],
          mineHp: mineHp,
          mineMax: raw['mineMax'] as int? ?? mineHp,
        )
          ..armed = raw['armed'] as bool? ?? false
          ..readyForWave = raw['ready'] as bool? ?? false
          ..waveHits = raw['waveHits'] as int? ?? 0,
      );
    }

    ballBoosters.clear();
    for (final raw in data['boosters'] as List<dynamic>? ?? []) {
      if (raw is! Map<String, dynamic>) continue;
      ballBoosters.add(
        BallBooster(
          row: raw['row'] as int? ?? 0,
          col: raw['col'] as int? ?? 0,
          bonus: raw['bonus'] as int? ?? 1,
        ),
      );
    }

    _lastBallSpeedMul = _ballSpeedMul();
    return true;
  }

  void _initEmptyGrid() {
    grid.clear();
    for (var r = 0; r < rows; r++) {
      grid.add(List<BreakerBrick?>.filled(cols, null));
    }
  }

  void _spawnStarterBrick() {
    final count = _bricksForStep(0).clamp(2, cols);
    final slots = List.generate(cols, (i) => i)..shuffle(_rng);
    for (var i = 0; i < count; i++) {
      grid[0][slots[i]] = _makeBrick(step: 0);
    }
    _seedBallBoosters(rowOnly: 0, extraChance: 0.20);
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
    if (s <= 0) return 2;
    if (s < 4) return 2 + _rng.nextInt(2);
    if (s < 10) return 3 + _rng.nextInt(2);
    if (s < 20) return 3 + _rng.nextInt(3);
    if (s < 35) return 4 + _rng.nextInt(3);
    return 5 + _rng.nextInt(2);
  }

  BreakerBrick _makeBrick({required int step}) {
    final roll = _rng.nextDouble();
    if (step >= 8 && roll < 0.05) {
      return BreakerBrick(hp: 0, kind: BrickKind.barrier, angle: 0);
    }
    final shape = BrickShapeUtil.pick(_rng);
    if (step >= 2 && roll < 0.35) {
      final hp = (2 + _rng.nextInt(3) + step ~/ 8).clamp(2, 18);
      return BreakerBrick(hp: hp, kind: BrickKind.heavy, angle: 0, shape: shape);
    }
    final hp = (1 + _rng.nextInt(2) + step ~/ 10 + level).clamp(1, 15);
    return BreakerBrick(hp: hp, kind: BrickKind.normal, angle: 0, shape: shape);
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

  LaserKind _randomLaserKind() {
    final roll = _rng.nextDouble();
    if (roll < 0.42) return LaserKind.vertical;
    if (roll < 0.84) return LaserKind.horizontal;
    return LaserKind.cross;
  }

  List<int> _emptyCells(int rowOnly) {
    final out = <int>[];
    for (var c = 0; c < cols; c++) {
      if (grid[rowOnly][c] != null) continue;
      if (_laserAt(rowOnly, c) != null) continue;
      if (_boosterAt(rowOnly, c) != null) continue;
      out.add(c);
    }
    return out;
  }

  int _pickBoosterBonus() {
    final roll = _rng.nextDouble();
    if (roll < 0.82) return 1;
    if (roll < 0.93) return 2;
    if (roll < 0.98) return step >= 8 ? 3 : 1;
    return step >= 18 ? 5 : 2;
  }

  void _seedBallBoosters({required int rowOnly, double extraChance = 0}) {
    final chance = extraChance > 0
        ? extraChance
        : math.min(0.26, 0.16 + step * 0.0008);
    var placed = 0;
    for (var c = 0; c < cols; c++) {
      if (placed >= 1) break;
      if (grid[rowOnly][c] != null) continue;
      if (_laserAt(rowOnly, c) != null) continue;
      if (_boosterAt(rowOnly, c) != null) continue;
      if (_rng.nextDouble() > chance) continue;
      ballBoosters.add(BallBooster(row: rowOnly, col: c, bonus: _pickBoosterBonus()));
      placed++;
    }
  }

  BallBooster? _boosterAt(int row, int col) {
    for (final b in ballBoosters) {
      if (b.row == row && b.col == col) return b;
    }
    return null;
  }

  void _seedBuriedLasers({required int rowOnly}) {
    if (step < 3) return;
    final chance = math.min(0.11, 0.055 + step * 0.001);
    for (var c = 0; c < cols; c++) {
      if (grid[rowOnly][c] != null) continue;
      if (_laserAt(rowOnly, c) != null) continue;
      if (_boosterAt(rowOnly, c) != null) continue;
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

  double rowTopPx(int r) => (gridTopY + r * brickH) * height + gridDriftY;
  double rowBottomPx(int r) => (gridTopY + (r + 1) * brickH) * height + gridDriftY;
  double colLeftPx(int c) => c * brickW * width + gridDriftX;

  ({double left, double top, double right, double bottom}) cellRect(int r, int c) {
    final left = colLeftPx(c) + 2;
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
    _fireCooldown = 0;
    for (final p in lasers) {
      if (p.armed) {
        p.readyForWave = true;
        p.resetVolleyCooldowns();
      }
    }
    _volleyTime = 0;
    phase = BreakerPhase.flying;
    _sfx('shoot');
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

  double _ballSpeedMul() {
    final g = gameplaySettings;
    if (g == null || !g.ballRampEnabled || _sessionTime < g.ballRampDelaySec) return 1;
    final t = math.min(_sessionTime - g.ballRampDelaySec, g.ballRampRiseSec);
    return 1 + (t / g.ballRampRiseSec) * (g.ballRampMaxClamped - 1);
  }

  void _syncBallSpeedMul() {
    final mul = _ballSpeedMul();
    if (mul == _lastBallSpeedMul) return;
    final ratio = mul / _lastBallSpeedMul;
    for (final b in balls) {
      if (!b.active) continue;
      b.vx *= ratio;
      b.vy *= ratio;
    }
    _lastBallSpeedMul = mul;
  }

  double _ballSpeed() => speed * _ballSpeedMul();

  void _spawnNextBall() {
    final isFirst = balls.isEmpty;
    final spd = _ballSpeed();
    balls.add(BreakerBall(
      x: launcherPx,
      y: launcherPy,
      vx: math.cos(aimAngle) * spd,
      vy: math.sin(aimAngle) * spd,
      isFirst: isFirst,
    ));
  }

  void update(double dt) {
    for (var i = laserBeams.length - 1; i >= 0; i--) {
      laserBeams[i].life -= dt;
      if (laserBeams[i].life <= 0) laserBeams.removeAt(i);
    }

    if (mode == BrickBreakerMode.siege &&
        phase != BreakerPhase.gameOver &&
        phase != BreakerPhase.levelClear) {
      _siegeUpdate(dt);
    }

    if (phase != BreakerPhase.gameOver && phase != BreakerPhase.levelClear) {
      _sessionTime += dt;
      _syncBallSpeedMul();
      _updateDangerWarning();
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
      _moveBall(b, dt);
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

  void _moveBall(BreakerBall b, double dt) {
    final travel = math.hypot(b.vx * dt, b.vy * dt);
    final steps = math.max(1, (travel / ballSubstepDist).ceil());
    final subDt = dt / steps;
    for (var s = 0; s < steps; s++) {
      b.x += b.vx * subDt;
      b.y += b.vy * subDt;
      _bounceOffWalls(b);
      _resolveBrickCollisions(b);
    }
  }

  void _resolveBrickCollisions(BreakerBall b) {
    for (var iter = 0; iter < ballMaxCollideIters; iter++) {
      var resolved = false;
      for (var r = 0; r < grid.length; r++) {
        for (var c = 0; c < grid[r].length; c++) {
          final shape = _brickShapeAt(r, c);
          if (shape == null) continue;

          final hit = BrickShapeUtil.ballHit(
            bx: b.x,
            by: b.y,
            br: ballRadius,
            cx: shape.cx,
            cy: shape.cy,
            hw: shape.hw,
            hh: shape.hh,
            angle: shape.angle,
            shape: shape.brickShape,
          );
          if (hit == null) continue;

          final brick = grid[r][c]!;
          if (brick.kind != BrickKind.barrier) {
            _damageBrick(r, c, 1);
          }
          final (vx, vy) = _reflectVel(b.vx, b.vy, hit.nx, hit.ny);
          b.vx = vx;
          b.vy = vy;
          final sep = math.max(hit.depth, 0) + ballSepSlop;
          b.x += hit.nx * sep;
          b.y += hit.ny * sep;
          if (iter == 0) _sfx('bounce');
          resolved = true;
          break;
        }
        if (resolved) break;
      }
      if (!resolved) break;
    }
  }

  void _hitBricks(BreakerBall b) {
    _resolveBrickCollisions(b);
  }

  void _hitLasers(BreakerBall b) {
    for (final p in lasers) {
      final rect = cellRect(p.row, p.col);
      if (b.x + ballRadius < rect.left ||
          b.x - ballRadius > rect.right ||
          b.y + ballRadius < rect.top ||
          b.y - ballRadius > rect.bottom) {
        continue;
      }

      if (!p.tryChargeFrom(b, _volleyTime)) continue;

      if (p.buried) {
        p.mineHp--;
        score += 5;
        if (p.mineHp <= 0) {
          p.armed = true;
          p.readyForWave = true;
          score += 25;
          _triggerLaser(p);
        }
        continue;
      }

      if (p.armed && p.readyForWave) {
        _triggerLaser(p);
      }
    }
  }

  void _triggerLaser(MapLaser laser) {
    _fireLaser(laser);
    laser.waveHits++;
    score += 8;
    _sfx('laser');
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
      final bonus = pick.bonus;
      ballsPerShot = (ballsPerShot + bonus).clamp(1, 24);
      score += 20 + bonus * 15;
      _sfx('booster');
    }
  }

  void _damageBrick(int r, int c, int amount, {bool fromLaser = false}) {
    final brick = grid[r][c];
    if (brick == null || !brick.alive) return;
    if (brick.kind == BrickKind.barrier) return;

    brick.hp -= amount;
    score += 10;
    _sfx('hit');

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
    for (var r = 0; r < rows; r++) {
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

  double _dangerLinePx() => dangerY * height;

  String _brickLineState(int r) {
    final line = _dangerLinePx();
    final top = rowTopPx(r);
    final bottom = rowBottomPx(r);
    if (top >= line) return 'over';
    if (bottom >= line) return 'warn';
    return 'safe';
  }

  void _enterGameOver() {
    _sfx('stopDangerWarn');
    phase = BreakerPhase.gameOver;
    dangerWarning = false;
    highScore = math.max(highScore, score);
    unawaited(BrickBreakerSave.clear(mode));
    _sfx('gameOver');
  }

  void _updateDangerWarning() {
    final wasWarn = dangerWarning;
    if (phase == BreakerPhase.gameOver || phase == BreakerPhase.levelClear) {
      dangerWarning = false;
      if (wasWarn) _sfx('stopDangerWarn');
      return;
    }
    var warn = false;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (!_countsTowardLoss(grid[r][c])) continue;
        if (_brickLineState(r) == 'warn') {
          warn = true;
          break;
        }
      }
      if (warn) break;
    }
    dangerWarning = warn;
    if (warn) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastWarnMs > 1400) {
        _lastWarnMs = now;
        _sfx('dangerWarn');
      }
    } else if (wasWarn) {
      _sfx('stopDangerWarn');
    }
  }

  bool _bottomRowBlocked() {
    for (var c = 0; c < cols; c++) {
      if (_countsTowardLoss(grid[rows - 1][c])) return true;
    }
    return false;
  }

  void _siegeUpdate(double dt) {
    _siegeTime += dt;
    final rowPx = brickH * height;
    final speed = 10 + level * 1.4 + step * 0.12;
    gridDriftY += speed * dt;
    gridDriftX = math.sin(_siegeTime * 0.9) * (8 + level * 0.35);
    while (gridDriftY >= rowPx) {
      if (_bottomRowBlocked()) {
        _enterGameOver();
        return;
      }
      gridDriftY -= rowPx;
      _shiftGridDown();
    }
    _checkGameOver();
  }

  bool _shiftGridDown() {
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
    final rowPx = brickH * height;
    gridDriftY = math.max(0, gridDriftY - rowPx);
    return false;
  }

  ({
    double cx,
    double cy,
    double hw,
    double hh,
    double angle,
    BrickShape brickShape,
    int r,
    int c,
  })? _brickShapeAt(int r, int c) {
    final brick = grid[r][c];
    if (brick == null || !brick.alive) return null;
    final left = colLeftPx(c) + 2;
    final top = rowTopPx(r) + 2;
    final bw = brickW * width - 4;
    final bh = rowBottomPx(r) - rowTopPx(r) - 4;
    return (
      cx: left + bw / 2,
      cy: top + bh / 2,
      hw: bw / 2,
      hh: bh / 2,
      angle: brick.angle,
      brickShape: brick.shape,
      r: r,
      c: c,
    );
  }

  (double vx, double vy) _reflectVel(double vx, double vy, double nx, double ny) {
    final dot = vx * nx + vy * ny;
    return (vx - 2 * dot * nx, vy - 2 * dot * ny);
  }

  void _shiftWallDown() {
    if (_bottomRowBlocked()) {
      _enterGameOver();
      return;
    }
    _shiftGridDown();
  }

  bool _ballOverlapsRect(
    double x,
    double y,
    double left,
    double top,
    double right,
    double bottom,
  ) {
    return !(x + ballRadius < left ||
        x - ballRadius > right ||
        y + ballRadius < top ||
        y - ballRadius > bottom);
  }

  ({double nx, double ny})? _firstBrickHitNormal(double x, double y) {
    for (var r = 0; r < grid.length; r++) {
      for (var c = 0; c < grid[r].length; c++) {
        final shape = _brickShapeAt(r, c);
        if (shape == null) continue;
        final hit = BrickShapeUtil.ballHit(
          bx: x,
          by: y,
          br: ballRadius,
          cx: shape.cx,
          cy: shape.cy,
          hw: shape.hw,
          hh: shape.hh,
          angle: shape.angle,
          shape: shape.brickShape,
        );
        if (hit != null) return hit;
      }
    }
    return null;
  }

  void _endVolley() {
    // Used lasers leave after the wave; unused armed ones carry to the next turn.
    lasers.removeWhere((p) => p.armed && p.waveHits > 0);
    for (final p in lasers) {
      if (p.armed) {
        p.readyForWave = false;
        p.waveHits = 0;
        p.resetVolleyCooldowns();
      }
    }

    step++;
    level++;

    if (_firstBallLandX != null) {
      launcherX = (_firstBallLandX! / width).clamp(0.08, 0.92);
    }

    _checkGameOver();
    if (phase == BreakerPhase.gameOver) return;

    _shiftWallDown();
    if (phase == BreakerPhase.gameOver) return;
    _spawnTopRow();
    _checkGameOver();
    if (phase == BreakerPhase.gameOver) return;

    if (_allClear()) {
      score += 100 * level;
      if (level >= 9999) score += 999999;
      _spawnLevel();
      phase = BreakerPhase.levelClear;
      _sfx('levelClear');
      onFullClear?.call(score);
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
        if (_brickLineState(r) == 'over') {
          _enterGameOver();
          return;
        }
      }
    }
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
      lastClearAward = null;
      lastScoreAward = null;
    }
  }

  void _bounceOffWalls(BreakerBall b) {
    if (b.x < ballRadius) {
      b.x = ballRadius;
      b.vx = b.vx.abs();
      _sfx('bounce');
    } else if (b.x > width - ballRadius) {
      b.x = width - ballRadius;
      b.vx = -b.vx.abs();
      _sfx('bounce');
    }
    if (b.y < ballRadius) {
      b.y = ballRadius;
      b.vy = b.vy.abs();
      _sfx('bounce');
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
    const stepLen = 3.0;
    const maxSteps = 480;
    final floor = launcherY * height;

    for (var i = 0; i < maxSteps; i++) {
      x += dx * stepLen;
      y += dy * stepLen;

      if (y >= floor) {
        dots.add(Offset(x.clamp(ballRadius, width - ballRadius), floor));
        break;
      }

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

      final hit = _firstBrickHitNormal(x, y);
      if (hit != null) {
        (dx, dy) = _reflectVel(dx, dy, hit.nx, hit.ny);
        // Step back out of the brick so the path does not draw through it.
        x -= dx * stepLen * 0.35;
        y -= dy * stepLen * 0.35;
        bounced = true;
      }

      if (bounced) {
        bounces.add(Offset(x, y));
        if (bounces.length > 14) break;
      } else if (i % 3 == 0) {
        dots.add(Offset(x, y));
      }
    }

    return (dots: dots, bounces: bounces);
  }
}
