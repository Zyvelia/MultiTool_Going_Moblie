import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum StepsCelebrationKind { goal, streak }

/// Brief magenta “flame” burst when goal or streak milestones fire.
class StepsCelebrationOverlay extends StatefulWidget {
  const StepsCelebrationOverlay({
    super.key,
    required this.kind,
    required this.streakDays,
    this.onDone,
  });

  final StepsCelebrationKind kind;
  final int streakDays;
  final VoidCallback? onDone;

  @override
  State<StepsCelebrationOverlay> createState() => _StepsCelebrationOverlayState();
}

class _StepsCelebrationOverlayState extends State<StepsCelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward().whenComplete(() => widget.onDone?.call());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return CustomPaint(
            painter: _FlamePainter(
              t: _ctrl.value,
              kind: widget.kind,
              streak: widget.streakDays,
            ),
            child: Center(
              child: Opacity(
                opacity: (1 - _ctrl.value).clamp(0.0, 1.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.kind == StepsCelebrationKind.goal
                          ? Icons.emoji_events_outlined
                          : Icons.local_fire_department,
                      size: 48,
                      color: AppColors.accentGlow,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.kind == StepsCelebrationKind.goal
                          ? 'Goal crushed'
                          : '${widget.streakDays}-day streak',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FlamePainter extends CustomPainter {
  _FlamePainter({
    required this.t,
    required this.kind,
    required this.streak,
  });

  final double t;
  final StepsCelebrationKind kind;
  final int streak;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.42);
    final rng = math.Random(7 + streak);
    for (var i = 0; i < 28; i++) {
      final angle = (i / 28) * math.pi * 2 + t * 2;
      final dist = (40 + rng.nextDouble() * 90) * (0.3 + t);
      final p = center +
          Offset(math.cos(angle) * dist, math.sin(angle) * dist - t * 60);
      final r = 6 + rng.nextDouble() * 14 * (1 - t);
      final paint = Paint()
        ..color = (i.isEven ? AppColors.accent : AppColors.accentGlow)
            .withValues(alpha: (1 - t) * 0.75);
      canvas.drawCircle(p, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FlamePainter old) => old.t != t;
}
