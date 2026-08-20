import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'brick_breaker_game.dart';
import 'brick_breaker_shapes.dart';

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
        ..color = game.dangerWarning
            ? Colors.redAccent.withValues(alpha: 0.95)
            : Colors.redAccent.withValues(alpha: 0.45)
        ..strokeWidth = game.dangerWarning ? 2.4 : 1.2,
    );

    for (final beam in game.laserBeams) {
      final alpha = (beam.life / 0.35).clamp(0.0, 1.0);
      final glowPaint = Paint()
        ..color = Colors.redAccent.withValues(alpha: 0.25 + alpha * 0.55)
        ..strokeWidth = 3 + alpha * 2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      final corePaint = Paint()
        ..color = Colors.white.withValues(alpha: alpha * 0.8)
        ..strokeWidth = 1.2;

      final x = game.colLeftPx(beam.col) + BrickBreakerGame.brickW * size.width * 0.5;
      final y = game.rowCenterY(beam.row);
      final yTop = game.rowTopPx(0);

      switch (beam.shape) {
        case LaserBeamShape.vertical:
          final yFullBottom = game.rowBottomPx(BrickBreakerGame.rows - 1);
          canvas.drawLine(Offset(x, yTop), Offset(x, yFullBottom), glowPaint);
          canvas.drawLine(Offset(x, yTop), Offset(x, yFullBottom), corePaint);
        case LaserBeamShape.horizontal:
          canvas.drawLine(Offset(0, y), Offset(size.width, y), glowPaint);
          canvas.drawLine(Offset(0, y), Offset(size.width, y), corePaint);
        case LaserBeamShape.cross:
          canvas.drawLine(Offset(0, y), Offset(size.width, y), glowPaint);
          canvas.drawLine(Offset(x, yTop), Offset(x, game.rowBottomPx(BrickBreakerGame.rows - 1)), glowPaint);
          canvas.drawLine(Offset(0, y), Offset(size.width, y), corePaint);
          canvas.drawLine(
            Offset(x, yTop),
            Offset(x, game.rowBottomPx(BrickBreakerGame.rows - 1)),
            corePaint,
          );
      }
    }

    for (var r = 0; r < game.grid.length; r++) {
      for (var c = 0; c < game.grid[r].length; c++) {
        final brick = game.grid[r][c];
        if (brick == null || !brick.alive) continue;

        final left = game.colLeftPx(c) + 2;
        final top = game.rowTopPx(r) + 2;
        final rect = Rect.fromLTWH(
          left,
          top,
          BrickBreakerGame.brickW * size.width - 4,
          game.rowBottomPx(r) - game.rowTopPx(r) - 4,
        );
        _drawBrick(canvas, rect, brick);
      }
    }

    for (final p in game.lasers) {
      final rect = game.cellRect(p.row, p.col);
      final cx = (rect.left + rect.right) / 2;
      final cy = (rect.top + rect.bottom) / 2;
      if (p.buried) {
        _drawBuriedLaser(canvas, Offset(cx, cy), p);
      } else {
        _drawArmedLaser(canvas, Offset(cx, cy), p);
      }
    }

    for (final pick in game.ballBoosters) {
      final rect = game.cellRect(pick.row, pick.col);
      final cx = (rect.left + rect.right) / 2;
      final cy = (rect.top + rect.bottom) / 2;
      _drawBallBooster(canvas, Offset(cx, cy), pick.bonus);
    }

    for (final portal in game.teleports) {
      final rect = game.cellRect(portal.row, portal.col);
      final cx = (rect.left + rect.right) / 2;
      final cy = (rect.top + rect.bottom) / 2;
      _drawTeleportPortal(
        canvas,
        Offset(cx, cy),
        rect.right - rect.left,
        portal.color,
        game.portalFacingAngle(portal),
      );
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

    if (game.sideFlash > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Color.fromRGBO(255, 82, 82, game.sideFlash * 0.42),
      );
    }
    if (game.nukePulse > 0) {
      canvas.drawRect(
        Rect.fromLTWH(2, 2, size.width - 4, size.height - 4),
        Paint()
          ..color = Colors.white.withValues(alpha: game.nukePulse * 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  void _drawBrick(Canvas canvas, Rect rect, BreakerBrick brick) {
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(brick.angle);
    final hw = rect.width / 2;
    final hh = rect.height / 2;
    final local = Rect.fromCenter(
      center: Offset.zero,
      width: rect.width,
      height: rect.height,
    );

    if (brick.kind == BrickKind.barrier) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(local, const Radius.circular(4)),
        Paint()..color = AppColors.border,
      );
      canvas.restore();
      return;
    }

    if (brick.shape == BrickShape.round) {
      if (brick.kind == BrickKind.heavy) {
        final t = (brick.hp / game.heavyBrickHpCap).clamp(0.0, 1.0);
        _fillBrick(
          canvas,
          local,
          Color.lerp(const Color(0xFF2A1030), AppColors.wine, t)!,
          Color.lerp(AppColors.wine, AppColors.accent, 1 - t)!,
        );
      } else {
        final t = (brick.hp / game.normalBrickHpCap).clamp(0.0, 1.0);
        _fillBrick(
          canvas,
          local,
          Color.lerp(AppColors.wine, AppColors.accent, 1 - t)!,
          AppColors.accentGlow,
        );
      }
    } else {
      final path = BrickShapeUtil.brickPath(brick.shape, hw, hh);
      if (brick.kind == BrickKind.heavy) {
        final t = (brick.hp / game.heavyBrickHpCap).clamp(0.0, 1.0);
        _fillBrickPath(
          canvas,
          path,
          Color.lerp(const Color(0xFF2A1030), AppColors.wine, t)!,
          Color.lerp(AppColors.wine, AppColors.accent, 1 - t)!,
        );
      } else {
        final t = (brick.hp / game.normalBrickHpCap).clamp(0.0, 1.0);
        _fillBrickPath(
          canvas,
          path,
          Color.lerp(AppColors.wine, AppColors.accent, 1 - t)!,
          AppColors.accentGlow,
        );
      }
    }
    _drawLabel(canvas, Offset.zero, '${brick.hp}');
    canvas.restore();
  }

  void _fillBrickPath(Canvas canvas, Path path, Color fill, Color stroke) {
    canvas.drawPath(
      path,
      Paint()..color = fill.withValues(alpha: 0.88),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round,
    );
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

  void _drawBuriedLaser(Canvas canvas, Offset c, MapLaser p) {
    final progress = 1 - (p.mineHp / p.mineMax);
    final color = _laserColor(p.kind);
    canvas.drawCircle(
      c,
      13,
      Paint()
        ..color = color.withValues(alpha: 0.12 + progress * 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      c,
      8,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    _drawLaserArrowIcon(canvas, c, p.kind, alpha: 0.35 + progress * 0.55);
    if (p.mineHp > 0) {
      _drawLabel(canvas, c, '${p.mineHp}');
    }
  }

  void _drawArmedLaser(Canvas canvas, Offset c, MapLaser p) {
    final color = _laserColor(p.kind);
    final active = p.readyForWave;
    final glow = active ? 0.35 : 0.18;
    final stroke = active ? 0.9 : 0.55;

    canvas.drawCircle(
      c,
      14,
      Paint()
        ..color = color.withValues(alpha: glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      c,
      10,
      Paint()
        ..color = color.withValues(alpha: stroke)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    _drawLaserArrowIcon(canvas, c, p.kind, alpha: active ? 1 : 0.65);

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

  Color _laserColor(LaserKind kind) {
    return switch (kind) {
      LaserKind.vertical => Colors.cyanAccent,
      LaserKind.horizontal => Colors.redAccent,
      LaserKind.cross => Colors.orangeAccent,
    };
  }

  void _drawLaserArrowIcon(Canvas canvas, Offset c, LaserKind kind, {required double alpha}) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: alpha)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    switch (kind) {
      case LaserKind.vertical:
        _drawArrow(canvas, c, const Offset(0, -7), paint);
        _drawArrow(canvas, c, const Offset(0, 7), paint);
      case LaserKind.horizontal:
        _drawArrow(canvas, c, const Offset(-7, 0), paint);
        _drawArrow(canvas, c, const Offset(7, 0), paint);
      case LaserKind.cross:
        _drawArrow(canvas, c, const Offset(0, -6), paint);
        _drawArrow(canvas, c, const Offset(0, 6), paint);
        _drawArrow(canvas, c, const Offset(-6, 0), paint);
        _drawArrow(canvas, c, const Offset(6, 0), paint);
    }
  }

  void _drawArrow(Canvas canvas, Offset from, Offset dir, Paint paint) {
    final tip = from + dir;
    final len = dir.distance;
    if (len < 1) return;
    final back = dir / len;
    final side = Offset(-back.dy, back.dx);
    canvas.drawLine(from, tip, paint);
    canvas.drawLine(tip, tip - back * 3 + side * 2.2, paint);
    canvas.drawLine(tip, tip - back * 3 - side * 2.2, paint);
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

  void _drawBallBooster(Canvas canvas, Offset c, int bonus) {
    final color = bonus >= 5
        ? const Color(0xFFFF9100)
        : bonus >= 3
            ? const Color(0xFFFFD54F)
            : bonus >= 2
                ? const Color(0xFF18FFFF)
                : AppColors.accentGlow;
    final orbR = bonus >= 5 ? 15.0 : bonus >= 3 ? 14.0 : 13.0;
    canvas.drawCircle(
      c,
      orbR,
      Paint()
        ..color = color.withValues(alpha: 0.32)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(c, 5, Paint()..color = Colors.white);
    final ring = Paint()
      ..color = color.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = bonus >= 5 ? 2.8 : 2.4;
    for (var i = 0; i < 4; i++) {
      final start = i * math.pi / 2 + 0.35;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: orbR - 2),
        start,
        math.pi / 2 - 0.5,
        false,
        ring,
      );
    }
    final plusTp = TextPainter(
      text: TextSpan(
        text: '+$bonus',
        style: TextStyle(
          color: Colors.white,
          fontSize: bonus >= 5 ? 10 : 9,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    plusTp.paint(canvas, Offset(c.dx + 8, c.dy - 10));
  }

  void _drawTeleportPortal(
    Canvas canvas,
    Offset c,
    double cellW,
    TeleportColor color,
    double angle,
  ) {
    final portalColor = color == TeleportColor.orange
        ? const Color(0xFFFF9100)
        : const Color(0xFF40C4FF);
    final r = cellW * 0.28;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()..color = portalColor.withValues(alpha: 0.22),
    );
    final ring = Paint()
      ..color = portalColor.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    const outerStart = -math.pi * 0.62;
    const outerSweep = math.pi * 1.24;
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: r * 0.72),
      outerStart,
      outerSweep,
      false,
      ring,
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: r * 0.44),
      outerStart + 0.28,
      outerSweep,
      false,
      ring,
    );
    canvas.drawCircle(
      Offset(r * 0.18, 0),
      r * 0.12,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BrickBreakerPainter oldDelegate) => true;
}
