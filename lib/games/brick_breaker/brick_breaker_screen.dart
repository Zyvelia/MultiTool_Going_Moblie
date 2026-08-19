import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../theme/app_colors.dart';
import 'brick_breaker_game.dart';
import 'brick_breaker_painter.dart';

class BrickBreakerScreen extends StatefulWidget {
  const BrickBreakerScreen({super.key});

  @override
  State<BrickBreakerScreen> createState() => _BrickBreakerScreenState();
}

class _BrickBreakerScreenState extends State<BrickBreakerScreen>
    with SingleTickerProviderStateMixin {
  final _game = BrickBreakerGame();
  late Ticker _ticker;
  Duration? _lastTick;

  @override
  void initState() {
    super.initState();
    _game.reset();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final prev = _lastTick;
    _lastTick = elapsed;
    if (prev == null) return;
    final dt = (elapsed - prev).inMicroseconds / 1e6;
    _game.update(dt.clamp(0, 0.032));
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails d, BoxConstraints box) {
    final nx = (d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0);
    final ny = (d.localPosition.dy / box.maxHeight).clamp(0.0, 1.0);
    if (_game.phase == BreakerPhase.aiming) {
      _game.movePaddle(nx);
      _game.setAimFromTouch(nx, ny);
    } else {
      _game.movePaddle(nx);
    }
    setState(() {});
  }

  void _onPanEnd(DragEndDetails _) {
    if (_game.phase == BreakerPhase.aiming) {
      _game.shoot();
      setState(() {});
    }
  }

  void _onTap() {
    if (_game.phase == BreakerPhase.levelClear) {
      _game.acknowledgeLevelClear();
      setState(() {});
    } else if (_game.phase == BreakerPhase.gameOver) {
      _game.reset();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Brick Breaker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Restart',
            onPressed: () {
              _game.reset();
              setState(() {});
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                _chip('Score', '${_game.score}'),
                const SizedBox(width: 8),
                _chip('Level', '${_game.level}'),
                const SizedBox(width: 8),
                _chip('Balls', '${_game.ballsPerShot}'),
                const Spacer(),
                Text(
                  'Best ${_game.highScore}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, box) {
                  return GestureDetector(
                    onPanUpdate: (d) => _onPanUpdate(d, box),
                    onPanEnd: _onPanEnd,
                    onTap: _onTap,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.08),
                            blurRadius: 24,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CustomPaint(
                              painter: BrickBreakerPainter(_game),
                            ),
                            if (_overlay() != null) _overlay()!,
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'Drag to aim · Release to shoot · Clear the wall before it reaches the red line',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accentMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        '$label $value',
        style: const TextStyle(
          color: AppColors.accentGlow,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget? _overlay() {
    if (_game.phase == BreakerPhase.gameOver) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.accent),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Game Over',
                style: TextStyle(
                  color: AppColors.accentGlow,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Score ${_game.score}',
                style: const TextStyle(color: AppColors.onSurface),
              ),
              const SizedBox(height: 12),
              const Text(
                'Tap to play again',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    if (_game.phase == BreakerPhase.levelClear) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.accent),
          ),
          child: Text(
            'Level ${_game.level - 1} cleared!\nTap for level ${_game.level}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.accentGlow),
          ),
        ),
      );
    }
    return null;
  }
}
