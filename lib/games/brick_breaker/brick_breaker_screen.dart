import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../theme/app_colors.dart';
import 'brick_breaker_audio.dart';
import 'brick_breaker_awards.dart';
import 'brick_breaker_game.dart';
import 'brick_breaker_gameplay_settings.dart';
import 'brick_breaker_mode.dart';
import 'brick_breaker_painter.dart';
import 'brick_breaker_save.dart';

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
  final _gameplay = BrickBreakerGameplaySettings();
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
    await _gameplay.load();
    final hs = await _audio.loadHighScore(key: widget.mode.highScoreKey);
    _game.highScore = hs;
    _game.gameplaySettings = _gameplay;
    _game.onSfx = _handleSfx;
    _game.onFullClear = _recordFullClear;
    await _game.configureMode(widget.mode, storedHighScore: hs);
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
      case 'stopDangerWarn':
        _audio.stopDangerWarn();
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
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            final s = _audio.settings;
            final gp = _gameplay;
            return DraggableScrollableSheet(
              initialChildSize: 0.72,
              minChildSize: 0.45,
              maxChildSize: 0.92,
              builder: (_, scrollCtrl) {
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.card.withValues(alpha: 0.98),
                        AppColors.surface,
                      ],
                    ),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    border: Border.all(color: AppColors.border.withValues(alpha: 0.9)),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        blurRadius: 32,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const Text(
                        'Settings',
                        style: TextStyle(
                          color: AppColors.accentGlow,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Sound & gameplay',
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      _settingsSectionCard(
                        title: 'Sound',
                        children: [
                          _toggle(ctx, setSheet, 'Music', s.music, 'music'),
                          _settingsSliderRow(
                            label: 'Music volume',
                            value: '${(s.musicVolume * 100).round()}%',
                            child: Slider(
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
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: _toggle(
                              ctx,
                              setSheet,
                              'Use my music files',
                              s.useCustomMusic,
                              'useCustomMusic',
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Soundtrack',
                            style: TextStyle(color: AppColors.muted, fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: _audio.settings.soundtrackPick,
                            dropdownColor: AppColors.card,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: AppColors.bg.withValues(alpha: 0.55),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppColors.border),
                              ),
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
                          const SizedBox(height: 4),
                          _toggle(ctx, setSheet, 'Ball (shoot & bounce)', s.ball, 'ball'),
                          _toggle(ctx, setSheet, 'Brick hits', s.bricks, 'bricks'),
                          _toggle(ctx, setSheet, 'Lasers', s.lasers, 'lasers'),
                          _toggle(ctx, setSheet, 'Powerups', s.powerups, 'powerups'),
                          _toggle(ctx, setSheet, 'Level clear & game over', s.ui, 'ui'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _settingsSectionCard(
                        title: 'Gameplay',
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Ball speed-up on long games',
                              style: TextStyle(color: AppColors.onSurface, fontSize: 14),
                            ),
                            value: gp.ballRampEnabled,
                            activeTrackColor: AppColors.accent.withValues(alpha: 0.45),
                            activeThumbColor: AppColors.accentGlow,
                            onChanged: (v) async {
                              gp.ballRampEnabled = v;
                              await gp.save();
                              setSheet(() {});
                            },
                          ),
                          Opacity(
                            opacity: gp.ballRampEnabled ? 1 : 0.42,
                            child: IgnorePointer(
                              ignoring: !gp.ballRampEnabled,
                              child: Column(
                                children: [
                                  _timeSettingRow(
                                    setSheet: setSheet,
                                    gp: gp,
                                    label: 'Grace period',
                                    unit: gp.ballRampDelayUnit,
                                    state: gp.delayControlState(),
                                    onUnitChanged: (unit) async {
                                      gp.ballRampDelayUnit = unit;
                                      await gp.save();
                                      setSheet(() {});
                                    },
                                    onDisplayChanged: (value) async {
                                      gp.setDelayFromDisplay(value);
                                      await gp.save();
                                      setSheet(() {});
                                    },
                                  ),
                                  _timeSettingRow(
                                    setSheet: setSheet,
                                    gp: gp,
                                    label: 'Time to max speed',
                                    unit: gp.ballRampRiseUnit,
                                    state: gp.riseControlState(),
                                    onUnitChanged: (unit) async {
                                      gp.ballRampRiseUnit = unit;
                                      await gp.save();
                                      setSheet(() {});
                                    },
                                    onDisplayChanged: (value) async {
                                      gp.setRiseFromDisplay(value);
                                      await gp.save();
                                      setSheet(() {});
                                    },
                                  ),
                                  _settingsSliderRow(
                                    label: 'Max speed multiplier',
                                    value: '${gp.ballRampMaxClamped.toStringAsFixed(2)}×',
                                    child: Slider(
                                      value: gp.ballRampMax,
                                      min: 1.25,
                                      max: 5,
                                      divisions: 75,
                                      activeColor: AppColors.accent,
                                      onChanged: (v) async {
                                        gp.ballRampMax = v;
                                        await gp.save();
                                        setSheet(() {});
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          _settingsHint('Speed ramp resets when you restart the game.'),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _settingsSectionCard({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: AppColors.bg.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.85)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.55),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.accentGlow,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const Divider(height: 20, thickness: 1, color: AppColors.border),
          ...children,
        ],
      ),
    );
  }

  Widget _timeSettingRow({
    required StateSetter setSheet,
    required BrickBreakerGameplaySettings gp,
    required String label,
    required BrickBreakerTimeUnit unit,
    required BrickBreakerTimeControlState state,
    required ValueChanged<BrickBreakerTimeUnit> onUnitChanged,
    required ValueChanged<double> onDisplayChanged,
  }) {
    return _settingsSliderRow(
      label: label,
      value: state.label,
      child: Row(
        children: [
          Expanded(
            child: Slider(
              value: state.display,
              min: state.min,
              max: state.max,
              divisions: gp.sliderDivisions(state),
              activeColor: AppColors.accent,
              onChanged: onDisplayChanged,
            ),
          ),
          const SizedBox(width: 8),
          _timeUnitDropdown(
            value: unit,
            onChanged: (next) {
              if (next == null) return;
              onUnitChanged(next);
            },
          ),
        ],
      ),
    );
  }

  Widget _timeUnitDropdown({
    required BrickBreakerTimeUnit value,
    required ValueChanged<BrickBreakerTimeUnit?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<BrickBreakerTimeUnit>(
          value: value,
          isDense: true,
          dropdownColor: AppColors.card,
          style: const TextStyle(color: AppColors.onSurface, fontSize: 12),
          items: BrickBreakerTimeUnit.values
              .map(
                (unit) => DropdownMenuItem(
                  value: unit,
                  child: Text(unit.label),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _settingsSliderRow({
    required String label,
    required String value,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: AppColors.onSurface, fontSize: 14),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accentMuted,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
                ),
                child: Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.accentGlow,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          child,
        ],
      ),
    );
  }

  Widget _settingsHint(String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.accentMuted.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.12)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35),
      ),
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
      dense: true,
      title: Text(label, style: const TextStyle(color: AppColors.onSurface, fontSize: 14)),
      value: value,
      activeTrackColor: AppColors.accent.withValues(alpha: 0.45),
      activeThumbColor: AppColors.accentGlow,
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
          onPressed: () async {
            await BrickBreakerSave.save(widget.mode, _game);
            if (!context.mounted) return;
            Navigator.of(context).pop();
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Restart',
            onPressed: () async {
              await BrickBreakerSave.clear(widget.mode);
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
