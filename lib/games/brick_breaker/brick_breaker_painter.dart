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

    // STEP label
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

    // Danger line
    final dangerY = BrickBreakerGame.dangerY * size.height;
    canvas.drawLine(
      Offset(0, dangerY),
      Offset(size.width, dangerY),
      Paint()
        ..color = Colors.redAccent.withValues(alpha: 0.45)
        ..strokeWidth = 1.2,
    );

    // Bricks
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

        if (brick.barrier) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(4)),
            Paint()..color = AppColors.border,
          );
          continue;
        }

        final t = (brick.hp / 12).clamp(0.0, 1.0);
        final fill = Color.lerp(AppColors.wine, AppColors.accent, 1 - t)!;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          Paint()..color = fill.withValues(alpha: 0.85),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          Paint()
            ..color = AppColors.accentGlow.withValues(alpha: 0.65)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );

        final tp = TextPainter(
          text: TextSpan(
            text: '${brick.hp}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2),
        );
      }
    }

    // Ball booster pickups
    for (final pick in game.boosters) {
      final rect = game.cellRect(pick.row, pick.col);
      final cx = (rect.left + rect.right) / 2;
      final cy = (rect.top + rect.bottom) / 2;
      _drawBooster(canvas, Offset(cx, cy));
    }

    // Dotted aim guide while aiming (shows wall bounces)
    if (game.phase == BreakerPhase.aiming) {
      final preview = game.aimPreview();
      final dotPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      for (final p in preview.dots) {
        canvas.drawCircle(p, 1.5, dotPaint);
      }
      final bouncePaint = Paint()
        ..color = AppColors.accentGlow.withValues(alpha: 0.75)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      for (final p in preview.bounces) {
        canvas.drawCircle(p, 2.8, bouncePaint);
      }
    }

    // In-flight balls
    for (final b in game.balls) {
      if (!b.active) continue;
      _drawBall(canvas, Offset(b.x, b.y), glow: true);
    }

    // Launcher ball + x count (only when aiming or between volleys)
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

  void _drawBooster(Canvas canvas, Offset c) {
    canvas.drawCircle(
      c,
      11,
      Paint()
        ..color = AppColors.accent.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(c, 4, Paint()..color = Colors.white);

    final ring = Paint()
      ..color = AppColors.accentGlow.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    for (var i = 0; i < 4; i++) {
      final start = i * math.pi / 2 + 0.35;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: 9),
        start,
        math.pi / 2 - 0.5,
        false,
        ring,
      );
    }
  }

  @override
  bool shouldRepaint(covariant BrickBreakerPainter oldDelegate) => true;
}
