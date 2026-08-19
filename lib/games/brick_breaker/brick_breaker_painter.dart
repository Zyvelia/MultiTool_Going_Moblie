import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'brick_breaker_game.dart';

class BrickBreakerPainter extends CustomPainter {
  final BrickBreakerGame game;

  BrickBreakerPainter(this.game);

  @override
  void paint(Canvas canvas, Size size) {
    game.resize(size.width, size.height);

    final stepTp = TextPainter(
      text: TextSpan(
        text: 'STEP ${game.step}',
        style: TextStyle(
          color: AppColors.accentGlow.withValues(alpha: 0.85),
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    stepTp.paint(canvas, const Offset(10, 10));

    final dangerY = BrickBreakerGame.dangerY * size.height;
    canvas.drawLine(
      Offset(0, dangerY),
      Offset(size.width, dangerY),
      Paint()
        ..color = Colors.redAccent.withValues(alpha: 0.45)
        ..strokeWidth = 1.2,
    );

    for (final beam in game.laserBeams) {
      final y = game.rowCenterY(beam.row);
      final alpha = (beam.life / 0.35).clamp(0.0, 1.0);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = Colors.redAccent.withValues(alpha: 0.25 + alpha * 0.55)
          ..strokeWidth = 3 + alpha * 2
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = Colors.white.withValues(alpha: alpha * 0.8)
          ..strokeWidth = 1.2,
      );
    }

    for (var r = 0; r < game.grid.length; r++) {
      for (var c = 0; c < game.grid[r].length; c++) {
        final brick = game.grid[r][c];
        if (brick == null || !brick.alive) continue;

        final left = c * BrickBreakerGame.brickW * size.width + 2;
        final top = r * BrickBreakerGame.brickH * size.height + 8;
        final rect = Rect.fromLTWH(
          left,
          top,
          BrickBreakerGame.brickW * size.width - 4,
          BrickBreakerGame.brickH * size.height - 4,
        );
        _drawBrick(canvas, rect, brick);
      }
    }

    for (final p in game.powerups) {
      final rect = game.cellRect(p.row, p.col);
      final cx = (rect.left + rect.right) / 2;
      final cy = (rect.top + rect.bottom) / 2;
      if (p.buried) {
        _drawBuriedPowerup(canvas, Offset(cx, cy), p);
      } else if (p.readyForWave) {
        _drawArmedPowerup(canvas, Offset(cx, cy), p);
      } else {
        _drawArmedPowerup(canvas, Offset(cx, cy), p, dimmed: true);
      }
    }

    if (game.phase == BreakerPhase.aiming) {
      final preview = game.aimPreview();
      final dotPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeCap = StrokeCap.round;
      for (final pt in preview.dots) {
        canvas.drawCircle(pt, 1.5, dotPaint);
      }
      final bouncePaint = Paint()
        ..color = AppColors.accentGlow.withValues(alpha: 0.75)
        ..strokeCap = StrokeCap.round;
      for (final pt in preview.bounces) {
        canvas.drawCircle(pt, 2.8, bouncePaint);
      }
    }

    for (final b in game.balls) {
      if (!b.active) continue;
      _drawBall(canvas, Offset(b.x, b.y), glow: true);
    }

    if (game.phase == BreakerPhase.aiming) {
      final lx = game.launcherPx;
      final ly = game.launcherPy;
      _drawBall(canvas, Offset(lx, ly), glow: true);

      final countTp = TextPainter(
        text: TextSpan(
          text: 'x${game.ballsPerShot}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      countTp.paint(canvas, Offset(lx + 10, ly - 8));
    }
  }

  void _drawBrick(Canvas canvas, Rect rect, BreakerBrick brick) {
    if (brick.kind == BrickKind.barrier) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()..color = AppColors.border,
      );
      return;
    }

    if (brick.kind == BrickKind.heavy) {
      final t = (brick.hp / 18).clamp(0.0, 1.0);
      _fillBrick(
        canvas,
        rect,
        Color.lerp(const Color(0xFF2A1030), AppColors.wine, t)!,
        Color.lerp(AppColors.wine, AppColors.accent, 1 - t)!,
      );
    } else {
      final t = (brick.hp / 15).clamp(0.0, 1.0);
      _fillBrick(
        canvas,
        rect,
        Color.lerp(AppColors.wine, AppColors.accent, 1 - t)!,
        AppColors.accentGlow,
      );
    }
    _drawLabel(canvas, rect.center, '${brick.hp}');
  }

  void _fillBrick(Canvas canvas, Rect rect, Color fill, Color stroke) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = fill.withValues(alpha: 0.88),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()
        ..color = stroke.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  void _drawLabel(Canvas canvas, Offset center, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  void _drawBuriedPowerup(Canvas canvas, Offset c, MapPowerup p) {
    final progress = 1 - (p.mineHp / p.mineMax);
    canvas.drawCircle(
      c,
      13,
      Paint()
        ..color = _kindColor(p.kind).withValues(alpha: 0.12 + progress * 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      c,
      8,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    _drawKindIcon(canvas, c, p.kind, alpha: 0.35 + progress * 0.45);
    _drawLabel(canvas, c, '${p.mineHp}');
  }

  void _drawArmedPowerup(Canvas canvas, Offset c, MapPowerup p, {bool dimmed = false}) {
    final glow = dimmed ? 0.15 : 0.35;
    final stroke = dimmed ? 0.45 : 0.85;

    canvas.drawCircle(
      c,
      14,
      Paint()
        ..color = _kindColor(p.kind).withValues(alpha: glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      c,
      10,
      Paint()
        ..color = _kindColor(p.kind).withValues(alpha: stroke)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    _drawKindIcon(canvas, c, p.kind, alpha: dimmed ? 0.55 : 1);

    if (p.waveHits > 0) {
      final chargeTp = TextPainter(
        text: TextSpan(
          text: '${p.waveHits}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      chargeTp.paint(canvas, Offset(c.dx + 10, c.dy - 12));
    }
  }

  Color _kindColor(PowerupKind kind) {
    return switch (kind) {
      PowerupKind.laser => Colors.redAccent,
      PowerupKind.bomb => Colors.orangeAccent,
      PowerupKind.ballPlus => AppColors.accentGlow,
    };
  }

  void _drawKindIcon(Canvas canvas, Offset c, PowerupKind kind, {required double alpha}) {
    switch (kind) {
      case PowerupKind.laser:
        _drawLaserIcon(canvas, c, alpha);
      case PowerupKind.bomb:
        _drawBombIcon(canvas, c, alpha);
      case PowerupKind.ballPlus:
        _drawPlusBallIcon(canvas, c, alpha);
    }
  }

  void _drawLaserIcon(Canvas canvas, Offset c, double alpha) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: alpha)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(c.dx - 7, c.dy), Offset(c.dx + 7, c.dy), paint);
  }

  void _drawBombIcon(Canvas canvas, Offset c, double alpha) {
    canvas.drawCircle(
      c.translate(0, 1),
      4.5,
      Paint()..color = Colors.white.withValues(alpha: alpha),
    );
  }

  void _drawPlusBallIcon(Canvas canvas, Offset c, double alpha) {
    canvas.drawCircle(c, 4, Paint()..color = Colors.white.withValues(alpha: alpha));
    final plus = Paint()
      ..color = AppColors.accent.withValues(alpha: alpha)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(c.dx - 2.5, c.dy), Offset(c.dx + 2.5, c.dy), plus);
    canvas.drawLine(Offset(c.dx, c.dy - 2.5), Offset(c.dx, c.dy + 2.5), plus);
  }

  void _drawBall(Canvas canvas, Offset c, {required bool glow}) {
    if (glow) {
      canvas.drawCircle(
        c,
        BrickBreakerGame.ballRadius + 2,
        Paint()
          ..color = AppColors.accent.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    canvas.drawCircle(c, BrickBreakerGame.ballRadius, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant BrickBreakerPainter oldDelegate) => true;
}
