import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'neon_drift_game.dart';

class NeonDriftPainter extends CustomPainter {
  final NeonDriftGame game;

  NeonDriftPainter(this.game);

  @override
  void paint(Canvas canvas, Size size) {
    game.resize(size.width, size.height);

    _drawGrid(canvas, size);

    for (final w in game.walls) {
      _drawWall(canvas, size, w);
    }

    for (final g in game.gemList) {
      if (g.taken) continue;
      _drawGem(canvas, size, g);
    }

    _drawPlayer(canvas, size);

    if (game.phase == DriftPhase.ready) {
      _drawCenterHint(canvas, size, 'TAP TO START\nDrag left / right');
    } else if (game.phase == DriftPhase.dead) {
      _drawCenterHint(canvas, size, 'CRASHED\nTap to retry');
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final line = Paint()
      ..color = AppColors.border.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var i = 1; i < 8; i++) {
      final x = size.width * i / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    final speedLines = (game.speed / 40).floor().clamp(3, 14);
    final scroll = (game.elapsed * game.speed * 0.15) % 40;
    for (var i = 0; i < speedLines; i++) {
      final y = (i * 40.0 + scroll) % size.height;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = AppColors.accent.withValues(alpha: 0.06)
          ..strokeWidth = 1,
      );
    }
  }

  void _drawWall(Canvas canvas, Size size, DriftWall w) {
    final top = w.y * size.height;
    final gapL = (w.gapCenter - w.gapHalf) * size.width;
    final gapR = (w.gapCenter + w.gapHalf) * size.width;
    final rectH = w.thickness;

    final fill = Paint()..color = AppColors.wine.withValues(alpha: 0.92);
    final edge = Paint()
      ..color = AppColors.accentGlow.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    if (gapL > 2) {
      final r = Rect.fromLTWH(0, top, gapL, rectH);
      canvas.drawRect(r, fill);
      canvas.drawRect(r, edge);
    }
    if (gapR < size.width - 2) {
      final r = Rect.fromLTWH(gapR, top, size.width - gapR, rectH);
      canvas.drawRect(r, fill);
      canvas.drawRect(r, edge);
    }

    canvas.drawLine(
      Offset(gapL, top),
      Offset(gapL, top + rectH),
      Paint()
        ..color = AppColors.accent
        ..strokeWidth = 2.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawLine(
      Offset(gapR, top),
      Offset(gapR, top + rectH),
      Paint()
        ..color = AppColors.accent
        ..strokeWidth = 2.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  void _drawGem(Canvas canvas, Size size, DriftGem g) {
    final c = Offset(g.x * size.width, g.y * size.height);
    canvas.drawCircle(
      c,
      9,
      Paint()
        ..color = AppColors.accent.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    final path = Path();
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2 + math.pi / 4;
      final p = Offset(c.dx + math.cos(a) * 6, c.dy + math.sin(a) * 6);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = AppColors.accentGlow);
  }

  void _drawPlayer(Canvas canvas, Size size) {
    final c = Offset(game.playerPx, game.playerPy);
    canvas.drawCircle(
      c,
      NeonDriftGame.playerRadius + 4,
      Paint()
        ..color = AppColors.accent.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(c, NeonDriftGame.playerRadius, Paint()..color = Colors.white);
    canvas.drawCircle(
      c,
      NeonDriftGame.playerRadius,
      Paint()
        ..color = AppColors.accentGlow.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _drawCenterHint(Canvas canvas, Size size, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.accentGlow.withValues(alpha: 0.9),
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width * 0.8);
    tp.paint(
      canvas,
      Offset(
        (size.width - tp.width) / 2,
        size.height * 0.38,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant NeonDriftPainter oldDelegate) => true;
}
