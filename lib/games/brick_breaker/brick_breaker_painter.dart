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

    // Grid glow
    final gridPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.35)
      ..strokeWidth = 0.5;
    for (var i = 0; i <= 10; i++) {
      final y = size.height * i / 10;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Danger line
    final dangerY = BrickBreakerGame.dangerY * size.height;
    canvas.drawLine(
      Offset(0, dangerY),
      Offset(size.width, dangerY),
      Paint()
        ..color = Colors.redAccent.withValues(alpha: 0.55)
        ..strokeWidth = 1.5,
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
          Paint()
            ..color = fill.withValues(alpha: 0.85)
            ..style = PaintingStyle.fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          Paint()
            ..color = AppColors.accentGlow.withValues(alpha: 0.7)
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
          Offset(
            rect.center.dx - tp.width / 2,
            rect.center.dy - tp.height / 2,
          ),
        );
      }
    }

    // Aim guide
    if (game.phase == BreakerPhase.aiming) {
      final px = game.paddleX * size.width;
      final py = BrickBreakerGame.paddleY * size.height - BrickBreakerGame.paddleH;
      final len = 80.0;
      final ex = px + math.cos(game.aimAngle) * len;
      final ey = py + math.sin(game.aimAngle) * len;
      canvas.drawLine(
        Offset(px, py),
        Offset(ex, ey),
        Paint()
          ..color = AppColors.accent.withValues(alpha: 0.45)
          ..strokeWidth = 2,
      );
    }

    // Balls
    for (final b in game.balls) {
      if (!b.active) continue;
      canvas.drawCircle(
        Offset(b.x, b.y),
        BrickBreakerGame.ballRadius,
        Paint()
          ..color = AppColors.accentGlow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(
        Offset(b.x, b.y),
        BrickBreakerGame.ballRadius - 1,
        Paint()..color = Colors.white,
      );
    }

    // Paddle
    final paddleRect = Rect.fromCenter(
      center: Offset(
        game.paddleX * size.width,
        BrickBreakerGame.paddleY * size.height,
      ),
      width: BrickBreakerGame.paddleW,
      height: BrickBreakerGame.paddleH,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(paddleRect, const Radius.circular(5)),
      Paint()
        ..color = AppColors.accent
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(paddleRect, const Radius.circular(5)),
      Paint()..color = AppColors.accentGlow,
    );
  }

  @override
  bool shouldRepaint(covariant BrickBreakerPainter oldDelegate) => true;
}
