import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../theme/app_colors.dart';
import 'brick_breaker_audio.dart';
import 'brick_breaker_awards.dart';
import 'brick_breaker_game.dart';
import 'brick_breaker_mode.dart';
import 'brick_breaker_painter.dart';

class BrickBreakerScreen extends StatefulWidget {
  final BrickBreakerMode mode;

  const BrickBreakerScreen({super.key, this.mode = BrickBreakerMode.endless});

  @override
  State<BrickBreakerScreen> createState() => _BrickBreakerScreenState();
}

class _BrickBreakerScreenState extends State<BrickBreakerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _game = BrickBreakerGame();
  final _audio = BrickBreakerAudio();
  late Ticker _ticker;
  Duration? _lastTick;
  bool _audioReady = false;
  int _awardScoreSnapshot = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
    _ticker = createTicker(_onTick)..start();
  }

  Future<void> _boot() async {
    await _audio.init();
    final hs = await _audio.loadHighScore(key: widget.mode.highScoreKey);
    _game.highScore = hs;
    _game.onSfx = _handleSfx;
    _game.onFullClear = _recordFullClear;
    _game.configureMode(widget.mode, storedHighScore: hs);
    await _audio.setLevel(_game.level);
    if (mounted) {
      setState(() => _audioReady = true);
    }
  }

  void _handleSfx(String name) {
    switch (name) {
      case 'shoot':
        _audio.shoot();
      case 'bounce':
        _audio.bounce();
      case 'hit':
        _audio.hit();
      case 'laser':
        _audio.laser();
      case 'booster':
        _audio.booster();
      case 'levelClear':
        _audio.levelClear();
      case 'dangerWarn':
        _audio.dangerWarn();
      case 'gameOver':
        _audio.gameOver();
        _persistHighScore();
    }
  }

  Future<void> _persistHighScore() async {
    if (_game.highScore > 0) {
      await _audio.saveHighScore(_game.highScore, key: widget.mode.highScoreKey);
    }
  }

  void _onTick(Duration elapsed) {
    final prev = _lastTick;
    _lastTick = elapsed;
    if (prev == null) return;
    final dt = (elapsed - prev).inMicroseconds / 1e6;
    final prevLevel = _game.level;
    _game.update(dt.clamp(0, 0.032));
    if (_game.score != _awardScoreSnapshot) {
      _awardScoreSnapshot = _game.score;
      _checkScoreAward();
    }
    if (_game.level != prevLevel && _audioReady) {
      _audio.setLevel(_game.level);
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_audioReady) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _audio.onAppPaused();
      case AppLifecycleState.resumed:
        _audio.onAppResumed();
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _audio.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails _, BoxConstraints box) {
    if (_audioReady) _audio.startBgm();
  }

  void _onPanUpdate(DragUpdateDetails d, BoxConstraints box) {
    if (_game.phase != BreakerPhase.aiming) return;
    final nx = (d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0);
    final ny = (d.localPosition.dy / box.maxHeight).clamp(0.0, 1.0);
    _game.setAimFromTouch(nx, ny);
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
      _awardScoreSnapshot = 0;
      _audio.setLevel(_game.level);
      _audio.startBgm(force: true);
      setState(() {});
    }
  }

  Future<void> _checkScoreAward() async {
    final bump = await BrickBreakerAwards.updateScore(_game.score);
    if (bump != null) _game.lastScoreAward = bump;
  }

  Future<void> _recordFullClear(int score) async {
    final award = await BrickBreakerAwards.recordFullClear(score);
    _game.lastClearAward = award;
    if (award.isNew) _game.lastScoreAward = award;
    _awardScoreSnapshot = score;
  }

  Future<void> _openSettings() async {
    if (!_audioReady) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            final s = _audio.settings;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Sound',
                      style: TextStyle(
                        color: AppColors.accentGlow,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _toggle(ctx, setSheet, 'Music', s.music, 'music'),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Music volume',
                            style: TextStyle(color: AppColors.onSurface, fontSize: 14),
                          ),
                        ),
                        Text(
                          '${(s.musicVolume * 100).round()}%',
                          style: const TextStyle(color: AppColors.muted, fontSize: 13),
                        ),
                      ],
                    ),
                    Slider(
                      value: s.musicVolume,
                      min: 0,
                      max: 1,
                      divisions: 20,
                      activeColor: AppColors.accent,
                      onChanged: (v) async {
                        await _audio.setMusicVolume(v);
                        setSheet(() {});
                        setState(() {});
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: _toggle(ctx, setSheet, 'Use my music files', s.useCustomMusic, 'useCustomMusic'),
                    ),
                    const SizedBox(height: 8),
                    const Text('Soundtrack', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _audio.settings.soundtrackPick,
                      dropdownColor: AppColors.card,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.card,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: _audio.soundtracks
                          .map((t) => DropdownMenuItem(value: t.id, child: Text(t.label)))
                          .toList(),
                      onChanged: (v) async {
                        if (v == null) return;
                        await _audio.setSoundtrackPick(v);
                        setSheet(() {});
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    _toggle(ctx, setSheet, 'Ball (shoot & bounce)', s.ball, 'ball'),
                    _toggle(ctx, setSheet, 'Brick hits', s.bricks, 'bricks'),
                    _toggle(ctx, setSheet, 'Lasers', s.lasers, 'lasers'),
                    _toggle(ctx, setSheet, 'Powerups (+1 orbs)', s.powerups, 'powerups'),
                    _toggle(ctx, setSheet, 'Level clear & game over', s.ui, 'ui'),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _toggle(
    BuildContext ctx,
    StateSetter setSheet,
    String label,
    bool value,
    String key,
  ) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(color: AppColors.onSurface, fontSize: 14)),
      value: value,
      activeThumbColor: AppColors.accent,
      onChanged: (v) async {
        await _audio.setBoolSetting(key, v);
        setSheet(() {});
        setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('Brick Breaker · ${widget.mode.title}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Mode menu',
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Sound settings',
            onPressed: _openSettings,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Restart',
            onPressed: () async {
              _game.reset();
              await _audio.setLevel(_game.level);
              await _audio.startBgm(force: true);
              setState(() {});
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    _chip('Score', '${_game.score}'),
                    const SizedBox(width: 8),
                    _chip('Level', '${_game.level}'),
                    const SizedBox(width: 8),
                    _chip('Mode', widget.mode.title),
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
              if (widget.mode == BrickBreakerMode.siege)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    'Siege: the wall keeps creeping — destroy bricks before they reach the line.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      return GestureDetector(
                        onPanStart: (d) => _onPanStart(d, box),
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
                                if (_game.phase == BreakerPhase.flying)
                                  Positioned(
                                    right: 6,
                                    top: 0,
                                    bottom: 0,
                                    child: Center(child: _dropSideButton()),
                                  ),
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
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Drag to aim · Release to shoot · Fly through +1 orbs & lasers',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dropSideButton() {
    return Material(
      color: AppColors.accentMuted,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          _game.dropAllBalls();
          setState(() {});
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 64,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.keyboard_double_arrow_down,
                color: AppColors.accentGlow,
                size: 26,
              ),
              SizedBox(height: 4),
              Text(
                'DROP',
                style: TextStyle(
                  color: AppColors.accentGlow,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
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
            style: const TextStyle(color: AppColors.accentGlow, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }
    return null;
  }
}
