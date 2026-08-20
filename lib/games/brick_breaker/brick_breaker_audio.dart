import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'brick_breaker_music_config.dart';

class BrickBreakerAudioSettings {
  bool music;
  bool useCustomMusic;
  String soundtrackPick;
  bool ball;
  bool bricks;
  bool lasers;
  bool powerups;
  bool ui;
  double musicVolume;

  BrickBreakerAudioSettings({
    this.music = true,
    this.useCustomMusic = true,
    this.soundtrackPick = 'auto',
    this.musicVolume = 0.42,
    this.ball = true,
    this.bricks = true,
    this.lasers = true,
    this.powerups = true,
    this.ui = true,
  });

  Map<String, dynamic> toJson() => {
        'music': music,
        'useCustomMusic': useCustomMusic,
        'soundtrackPick': soundtrackPick,
        'musicVolume': musicVolume,
        'ball': ball,
        'bricks': bricks,
        'lasers': lasers,
        'powerups': powerups,
        'ui': ui,
      };

  factory BrickBreakerAudioSettings.fromJson(Map<String, dynamic> json) {
    final vol = (json['musicVolume'] as num?)?.toDouble() ?? 0.42;
    return BrickBreakerAudioSettings(
      music: json['music'] as bool? ?? true,
      useCustomMusic: json['useCustomMusic'] as bool? ?? true,
      soundtrackPick: json['soundtrackPick'] as String? ?? 'auto',
      musicVolume: vol.clamp(0.0, 1.0),
      ball: json['ball'] as bool? ?? true,
      bricks: json['bricks'] as bool? ?? true,
      lasers: json['lasers'] as bool? ?? true,
      powerups: json['powerups'] as bool? ?? true,
      ui: json['ui'] as bool? ?? true,
    );
  }
}

/// BGM + lightweight haptic SFX — mirrors web GameAudio behavior.
class BrickBreakerAudio {
  static const _prefsKey = 'zs_brick_breaker_audio';
  static const _hsKey = 'zs_brick_breaker_high_score';

  final AudioPlayer _player = AudioPlayer();
  BrickBreakerAudioSettings settings = BrickBreakerAudioSettings();
  int _currentLevel = 1;
  String? _playingAsset;
  String? _randomAsset;
  bool _pausedForLifecycle = false;
  DateTime _lastBounce = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastHit = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastDangerWarn = DateTime.fromMillisecondsSinceEpoch(0);
  AudioPlayer? _warnPlayer;
  bool _warnAssetReady = false;
  StreamSubscription<PlayerState>? _playerSub;

  List<BrickBreakerSoundtrackOption> get soundtracks {
    final list = <BrickBreakerSoundtrackOption>[
      const BrickBreakerSoundtrackOption(
        id: 'auto',
        label: 'Auto (changes with level)',
      ),
      const BrickBreakerSoundtrackOption(
        id: 'random',
        label: 'Random (shuffle on end)',
      ),
    ];
    for (final asset in brickBreakerMusicPool) {
      final name = asset.split('/').last;
      String label = name;
      for (final entry in brickBreakerMusicLevels) {
        if (entry.asset == asset) {
          label = '$name (level ${entry.level}+)';
          break;
        }
      }
      for (final extra in brickBreakerExtraMusic) {
        if (extra.asset == asset) {
          label = extra.label;
          break;
        }
      }
      list.add(BrickBreakerSoundtrackOption(
        id: asset,
        label: label,
        asset: asset,
      ));
    }
    return list;
  }

  String _pickRandomAsset({String? exclude}) {
    final pool = brickBreakerMusicPool;
    if (pool.isEmpty) return brickBreakerDefaultMusic;
    if (pool.length == 1) return pool.first;
    final candidates = exclude == null
        ? pool
        : pool.where((a) => a != exclude).toList();
    final pickFrom = candidates.isEmpty ? pool : candidates;
    return pickFrom[Random().nextInt(pickFrom.length)];
  }

  void _refreshRandomAsset({required bool forceNew}) {
    _randomAsset = _pickRandomAsset(exclude: forceNew ? _randomAsset ?? _playingAsset : null);
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        settings = BrickBreakerAudioSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    if (settings.soundtrackPick == 'random') {
      _refreshRandomAsset(forceNew: false);
    }
    _playerSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        unawaited(_onBgmCompleted());
      }
    });
    await _applyLoopMode();
    await _applyVolume();
    await _initWarnSfx();
  }

  Future<void> _applyLoopMode() async {
    await _player.setLoopMode(
      settings.soundtrackPick == 'random' ? LoopMode.off : LoopMode.one,
    );
  }

  Future<void> _onBgmCompleted() async {
    if (!settings.music || !settings.useCustomMusic) return;
    if (settings.soundtrackPick != 'random') return;
    _refreshRandomAsset(forceNew: true);
    final asset = _randomAsset;
    if (asset == null) return;
    await _playAsset(asset, restart: true);
  }

  Future<void> _initWarnSfx() async {
    try {
      final player = AudioPlayer();
      await player.setAsset(brickBreakerWarnSound);
      await player.setVolume(brickBreakerWarnVolume);
      _warnPlayer?.dispose();
      _warnPlayer = player;
      _warnAssetReady = true;
    } catch (_) {
      _warnAssetReady = false;
    }
  }

  void dangerWarn() {
    if (!settings.ui) return;
    final now = DateTime.now();
    if (now.difference(_lastDangerWarn).inMilliseconds < 1400) return;
    _lastDangerWarn = now;
    if (_warnAssetReady && _warnPlayer != null) {
      _warnPlayer!
        ..setVolume(brickBreakerWarnVolume)
        ..seek(Duration.zero)
        ..play();
      return;
    }
    HapticFeedback.mediumImpact();
  }

  Future<void> _applyVolume() async {
    await _player.setVolume(settings.musicVolume.clamp(0.0, 1.0));
  }

  Future<void> setMusicVolume(double level) async {
    settings.musicVolume = level.clamp(0.0, 1.0);
    await saveSettings();
    await _applyVolume();
  }

  Future<int> loadHighScore({String? key}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key ?? _hsKey) ?? 0;
  }

  Future<void> saveHighScore(int score, {String? key}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key ?? _hsKey, score);
  }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(settings.toJson()));
    await _syncBgm(force: false);
  }

  Future<void> setBoolSetting(String key, bool value) async {
    switch (key) {
      case 'music':
        settings.music = value;
      case 'useCustomMusic':
        settings.useCustomMusic = value;
      case 'ball':
        settings.ball = value;
      case 'bricks':
        settings.bricks = value;
      case 'lasers':
        settings.lasers = value;
      case 'powerups':
        settings.powerups = value;
      case 'ui':
        settings.ui = value;
    }
    await saveSettings();
  }

  Future<void> setSoundtrackPick(String id) async {
    settings.soundtrackPick = id;
    if (id == 'random') {
      _refreshRandomAsset(forceNew: false);
    } else {
      _randomAsset = null;
    }
    await saveSettings();
    await _applyLoopMode();
    await _syncBgm(force: true);
  }

  String? _assetForLevel(int level) {
    String? pick;
    for (final entry in brickBreakerMusicLevels) {
      if (level >= entry.level) pick = entry.asset;
    }
    return pick ?? brickBreakerDefaultMusic;
  }

  String? _resolveAsset() {
    if (!settings.music || !settings.useCustomMusic) return null;
    if (settings.soundtrackPick == 'random') {
      _randomAsset ??= _pickRandomAsset();
      return _randomAsset;
    }
    if (settings.soundtrackPick != 'auto') {
      for (final t in soundtracks) {
        if (t.id == settings.soundtrackPick && t.asset != null) return t.asset;
      }
    }
    return _assetForLevel(_currentLevel);
  }

  Future<void> setLevel(int level) async {
    _currentLevel = level;
    if (settings.soundtrackPick == 'random') {
      _refreshRandomAsset(forceNew: true);
      final asset = _randomAsset;
      if (asset != null) await _playAsset(asset, restart: false);
      return;
    }
    if (settings.soundtrackPick != 'auto') return;
    final next = _assetForLevel(level);
    if (next != null && next != _playingAsset) {
      await _playAsset(next, restart: false);
    }
  }

  Future<void> _syncBgm({required bool force}) async {
    final asset = _resolveAsset();
    if (asset == null) {
      await stopBgm(reset: true);
      return;
    }
    if (!force && asset == _playingAsset && _player.playing) return;
    await _playAsset(asset, restart: force);
  }

  Future<void> _playAsset(String asset, {required bool restart}) async {
    if (!settings.music || !settings.useCustomMusic) return;
    if (_playingAsset == asset && _player.playing && !restart) return;

    if (_playingAsset != asset) {
      await _player.setAsset(asset);
      _playingAsset = asset;
    } else if (restart) {
      await _player.seek(Duration.zero);
    }

    _pausedForLifecycle = false;
    await _applyLoopMode();
    await _applyVolume();
    if (!_player.playing) {
      await _player.play();
    }
  }

  Future<void> startBgm({bool force = false}) async {
    await _syncBgm(force: force);
  }

  Future<void> stopBgm({bool reset = false}) async {
    await _player.pause();
    if (reset) {
      await _player.seek(Duration.zero);
      _playingAsset = null;
    }
    _pausedForLifecycle = false;
  }

  Future<void> onAppPaused() async {
    if (!_player.playing) return;
    _pausedForLifecycle = true;
    await _player.pause();
  }

  Future<void> onAppResumed() async {
    if (!_pausedForLifecycle || !settings.music || !settings.useCustomMusic) return;
    if (_playingAsset == null) {
      await _syncBgm(force: false);
      return;
    }
    await _player.play();
    _pausedForLifecycle = false;
  }

  void shoot() {
    if (!settings.ball) return;
    HapticFeedback.selectionClick();
  }

  void bounce() {
    if (!settings.ball) return;
    final now = DateTime.now();
    if (now.difference(_lastBounce).inMilliseconds < 55) return;
    _lastBounce = now;
  }

  void hit() {
    if (!settings.bricks) return;
    final now = DateTime.now();
    if (now.difference(_lastHit).inMilliseconds < 35) return;
    _lastHit = now;
    HapticFeedback.lightImpact();
  }

  void laser() {
    if (!settings.lasers) return;
    HapticFeedback.mediumImpact();
  }

  void booster() {
    if (!settings.powerups) return;
    HapticFeedback.heavyImpact();
  }

  Future<void> gameOver() async {
    if (!settings.ui) return;
    await stopBgm(reset: true);
    HapticFeedback.heavyImpact();
  }

  void levelClear() {
    if (!settings.ui) return;
    HapticFeedback.mediumImpact();
  }

  Future<void> dispose() async {
    await _playerSub?.cancel();
    await _warnPlayer?.dispose();
    await _player.dispose();
  }
}
