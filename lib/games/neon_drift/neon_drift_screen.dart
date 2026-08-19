import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../theme/app_colors.dart';
import 'neon_drift_game.dart';
import 'neon_drift_painter.dart';

class NeonDriftScreen extends StatefulWidget {
  const NeonDriftScreen({super.key});

  @override
  State<NeonDriftScreen> createState() => _NeonDriftScreenState();
}

class _NeonDriftScreenState extends State<NeonDriftScreen>
    with SingleTickerProviderStateMixin {
  final _game = NeonDriftGame();
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
    _game.setPlayerX(nx);
    setState(() {});
  }

  void _onTap() {
    switch (_game.phase) {
      case DriftPhase.ready:
        _game.start();
      case DriftPhase.dead:
        _game.retry();
      case DriftPhase.playing:
        break;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Neon Drift'),
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
                _chip('Gems', '${_game.gems}'),
                const SizedBox(width: 8),
                _chip('Speed', '${_game.speed.toInt()}'),
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
                    onTap: _onTap,
                    child: Transform.translate(
                      offset: _game.shakeOffset,
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
                          child: CustomPaint(
                            painter: NeonDriftPainter(_game),
                            size: Size(box.maxWidth, box.maxHeight),
                          ),
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
              'Endless dodge — drag through the gaps · grab gems · speed never stops',
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
}
