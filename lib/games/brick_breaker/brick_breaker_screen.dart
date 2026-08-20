import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../theme/app_colors.dart';
import 'brick_breaker_audio.dart';
import 'brick_breaker_game.dart';
import 'brick_breaker_gameplay_settings.dart';
import 'brick_breaker_leaderboard.dart';
import 'brick_breaker_mode.dart';
import 'brick_breaker_painter.dart';
import '../../services/settings_service.dart';
import 'brick_breaker_save.dart';
import 'brick_breaker_side_powerups.dart';

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
  final _leaderboard = BrickBreakerLeaderboardService();
  late Ticker _ticker;
  Duration? _lastTick;
  bool _audioReady = false;
  String? _lastLeaderboardMessage;
  SidePowerMeta? _sideMeta;
  final _sideRng = math.Random();

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
    await _game.configureMode(widget.mode, storedHighScore: hs);
    _sideMeta = await SidePowerMeta.load();
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
        _submitLeaderboardScore();
    }
  }

  Future<void> _submitLeaderboardScore() async {
    final result = await _leaderboard.submit(
      mode: widget.mode,
      score: _game.score,
    );
    if (!mounted) return;
    if (result.ok) {
      setState(() {
        _lastLeaderboardMessage = result.rank != null
            ? 'Leaderboard: #${result.rank} with ${_game.score} pts!'
            : 'Score submitted to leaderboard!';
      });
    } else if (result.error == 'no_name') {
      setState(() {
        _lastLeaderboardMessage = 'Set your name in Leaderboard to post scores.';
      });
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
      _lastLeaderboardMessage = null;
      _audio.setLevel(_game.level);
      _audio.startBgm(force: true);
      setState(() {});
    }
  }

  Future<void> _openLeaderboard() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LeaderboardSheet(
        mode: widget.mode,
        leaderboard: _leaderboard,
      ),
    );
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
                                      value: gp.ballRampMaxClamped,
                                      min: 1.25,
                                      max: BrickBreakerGameplaySettings.ballRampMaxCap,
                                      divisions: 35,
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
            icon: const Icon(Icons.leaderboard),
            tooltip: 'Leaderboard',
            onPressed: _openLeaderboard,
          ),
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
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(child: _sidePanel()),
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
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
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Drag to aim · Daily chest on the side (resets each week)',
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

  Widget _sidePanel() {
    final meta = _sideMeta;
    if (meta == null) return const SizedBox(width: 58);

    return SizedBox(
      width: 58,
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _chestButton(meta),
            const SizedBox(height: 8),
            for (final type in SidePowerType.values) ...[
              _sidePowerButton(meta, type),
              if (type != SidePowerType.values.last) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chestButton(SidePowerMeta meta) {
    final ready = meta.chestReady;
    return Material(
      color: ready
          ? const Color(0xFFFFC107).withValues(alpha: 0.28)
          : const Color(0xFFFFC107).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: ready ? _openChest : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 58,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: ready
                  ? const Color(0xFFFFD54F).withValues(alpha: 0.65)
                  : AppColors.border,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎁', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 2),
              const Text(
                'CHEST',
                style: TextStyle(
                  color: Color(0xFFFFD54F),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                formatChestStatus(meta),
                style: TextStyle(
                  color: ready ? const Color(0xFFFFE082) : AppColors.muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sidePowerButton(SidePowerMeta meta, SidePowerType type) {
    final def = sidePowerDefs[type]!;
    final count = meta.count(type);
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: count > 0 ? () => _useSidePower(type) : null,
        borderRadius: BorderRadius.circular(14),
        child: Opacity(
          opacity: count > 0 ? 1 : 0.35,
          child: Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: def.color.withValues(alpha: 0.22),
                        border: Border.all(color: def.color.withValues(alpha: 0.55)),
                      ),
                      child: Text(
                        def.icon,
                        style: TextStyle(
                          color: def.color,
                          fontSize: def.icon.length > 1 ? 11 : 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      def.label.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: -2,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _useSidePower(SidePowerType type) async {
    final meta = _sideMeta;
    if (meta == null || meta.count(type) <= 0) return;
    if (_game.phase == BreakerPhase.gameOver ||
        _game.phase == BreakerPhase.levelClear) {
      return;
    }
    if (!_game.useSidePower(type)) return;
    final inv = Map<SidePowerType, int>.from(meta.inventory);
    inv[type] = math.max(0, (inv[type] ?? 0) - 1);
    _sideMeta = meta.copyWith(inventory: inv);
    await _sideMeta!.save();
    if (mounted) setState(() {});
  }

  Future<void> _openChest() async {
    var meta = _sideMeta?.normalized();
    if (meta == null || !meta.chestReady) return;
    final day = meta.nextChestDay;
    final lastDaily = day >= 7;
    final rewards = pickChestRewards(_sideRng, lastDailyOfWeek: lastDaily);
    final inv = Map<SidePowerType, int>.from(meta.inventory);
    for (final e in rewards.entries) {
      inv[e.key] = (inv[e.key] ?? 0) + e.value;
    }
    _sideMeta = meta.copyWith(
      inventory: inv,
      lastChestDate: _dateKeyNow(),
      chestsThisWeek: math.min(7, meta.chestsThisWeek + 1),
    );
    await _sideMeta!.save();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Chest opened!',
          style: TextStyle(color: AppColors.accentGlow),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              lastDaily
                  ? 'Weekly finale — guaranteed Board Nuke 💥 plus bonus powerups!'
                  : 'Daily chest (${day}/7 this week). Come back tomorrow!',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            for (final e in rewards.entries)
              if (e.value > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${sidePowerDefs[e.key]!.icon} ${sidePowerDefs[e.key]!.title} ×${e.value}',
                    style: const TextStyle(color: AppColors.onSurface),
                  ),
                ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Nice!'),
          ),
        ],
      ),
    );
    if (mounted) setState(() {});
  }

  String _dateKeyNow() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
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
              if (_lastLeaderboardMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _lastLeaderboardMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.accentGlow, fontSize: 12),
                ),
              ],
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

class _LeaderboardSheet extends StatefulWidget {
  final BrickBreakerMode mode;
  final BrickBreakerLeaderboardService leaderboard;

  const _LeaderboardSheet({
    required this.mode,
    required this.leaderboard,
  });

  @override
  State<_LeaderboardSheet> createState() => _LeaderboardSheetState();
}

class _LeaderboardSheetState extends State<_LeaderboardSheet> {
  final _nameCtrl = TextEditingController();
  final _apiCtrl = TextEditingController();
  late BrickBreakerMode _viewMode;
  BrickBreakerLeaderboardSource _source = BrickBreakerLeaderboardSource.pc;
  String _connectionHint = '';
  bool _loading = true;
  String _status = 'Loading…';
  List<LeaderboardEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _viewMode = widget.mode;
    _boot();
  }

  Future<void> _boot() async {
    final name = await widget.leaderboard.getName();
    final public = await SettingsService().getBrickBreakerLeaderboardUrl();
    final source = await widget.leaderboard.getSource();
    final hint = await widget.leaderboard.describeConnection();
    if (mounted) {
      _nameCtrl.text = name ?? '';
      _apiCtrl.text = public ?? '';
      _source = source;
      _connectionHint = hint;
    }
    await _load();
  }

  Future<void> _setSource(BrickBreakerLeaderboardSource source) async {
    await widget.leaderboard.setSource(source);
    final hint = await widget.leaderboard.describeConnection();
    if (!mounted) return;
    setState(() {
      _source = source;
      _connectionHint = hint;
    });
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _status = 'Loading…';
    });
    final hint = await widget.leaderboard.describeConnection();
    final result = await widget.leaderboard.fetch(mode: _viewMode);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _connectionHint = hint;
      if (!result.ok) {
        _status = _source == BrickBreakerLeaderboardSource.public
            ? 'Public leaderboard offline — check API URL and try again.'
            : 'PC leaderboard offline — open Brick Breaker on your PC (port 8450) and confirm Tailscale hostname in app settings.';
        _entries = [];
      } else {
        _status = result.entries.isEmpty
            ? 'No scores yet — be the first!'
            : 'Top ${result.entries.length} — ${_viewMode.title}';
        _entries = result.entries;
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _apiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final you = _nameCtrl.text.trim().toLowerCase();
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (context, scrollCtrl) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: ListView(
            controller: scrollCtrl,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const Text(
                'Leaderboard',
                style: TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _modeTab('Endless', BrickBreakerMode.endless),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _modeTab('Siege', BrickBreakerMode.siege),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Leaderboard source',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _sourceTab(
                      'My PC',
                      BrickBreakerLeaderboardSource.pc,
                      'Tailscale :8450',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _sourceTab(
                      'Public',
                      BrickBreakerLeaderboardSource.public,
                      'Cloud / web board',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _connectionHint,
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                maxLength: 20,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  counterText: '',
                  hintText: 'Shown on the board',
                ),
                onSubmitted: (_) async {
                  await widget.leaderboard.setName(_nameCtrl.text);
                  _load();
                },
              ),
              if (_source == BrickBreakerLeaderboardSource.public) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _apiCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Public API URL',
                    hintText: SettingsService.brickBreakerLeaderboardDefaultUrl,
                  ),
                  onSubmitted: (_) => _saveApiUrl(),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _saveApiUrl,
                    child: const Text('Save URL & refresh'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.accentMuted.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  _status,
                  style: const TextStyle(color: AppColors.onSurface, fontSize: 12),
                ),
              ),
              const SizedBox(height: 10),
              if (_loading)
                const Center(child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ))
              else if (_entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Play a run — scores submit on game over when your name is set.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                )
              else
                ..._entries.map((e) {
                  final isYou = you.isNotEmpty && e.name.toLowerCase() == you;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isYou ? AppColors.accentMuted : AppColors.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isYou
                            ? AppColors.accent.withValues(alpha: 0.45)
                            : AppColors.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 32,
                          child: Text(
                            '#${e.rank}',
                            style: const TextStyle(
                              color: AppColors.accentGlow,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            e.name,
                            style: const TextStyle(
                              color: AppColors.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          BrickBreakerLeaderboardService.formatScore(e.score),
                          style: const TextStyle(
                            color: AppColors.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          BrickBreakerLeaderboardService.formatWhen(e.ts),
                          style: const TextStyle(color: AppColors.muted, fontSize: 10),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Widget _sourceTab(String label, BrickBreakerLeaderboardSource source, String subtitle) {
    final active = _source == source;
    return OutlinedButton(
      onPressed: () => _setSource(source),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        backgroundColor: active ? AppColors.accentMuted : AppColors.card,
        foregroundColor: active ? AppColors.accentGlow : AppColors.muted,
        side: BorderSide(
          color: active ? AppColors.accent.withValues(alpha: 0.45) : AppColors.border,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  Widget _modeTab(String label, BrickBreakerMode mode) {
    final active = _viewMode == mode;
    return OutlinedButton(
      onPressed: () async {
        await widget.leaderboard.setName(_nameCtrl.text);
        setState(() => _viewMode = mode);
        _load();
      },
      style: OutlinedButton.styleFrom(
        backgroundColor: active ? AppColors.accentMuted : AppColors.card,
        foregroundColor: active ? AppColors.accentGlow : AppColors.muted,
        side: BorderSide(
          color: active ? AppColors.accent.withValues(alpha: 0.45) : AppColors.border,
        ),
      ),
      child: Text(label),
    );
  }

  Future<void> _saveApiUrl() async {
    final settings = SettingsService();
    await settings.setBrickBreakerLeaderboardUrl(_apiCtrl.text);
    if (_source != BrickBreakerLeaderboardSource.public) {
      await widget.leaderboard.setSource(BrickBreakerLeaderboardSource.public);
      if (mounted) setState(() => _source = BrickBreakerLeaderboardSource.public);
    }
    await _load();
  }
}
