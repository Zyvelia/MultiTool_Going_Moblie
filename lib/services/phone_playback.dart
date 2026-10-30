import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;

/// Playback surface the music screens listen to.
///
/// Streams from the PC stay on [justAudio]. A file already on an Android
/// phone is played by libmpv, which opens the file itself. That is what
/// can read a video-sized download Android 11's ExoPlayer rejects.
class PhonePlayback {
  PhonePlayback(this.justAudio) {
    _justState = justAudio.playerStateStream.listen((state) {
      if (_androidFile) return;
      _lastState = state;
      if (!_states.isClosed) _states.add(state);
    });
    _justPos = justAudio.positionStream.listen((position) {
      if (_androidFile) return;
      _lastPosition = position;
      if (!_positions.isClosed) _positions.add(position);
    });
  }

  final AudioPlayer justAudio;

  /// Fired when an Android local file reaches the end.
  void Function()? onAndroidEnded;

  /// Fired when an Android local file fails before it has really started.
  void Function(String message)? onAndroidError;

  Player? _mpv;
  StreamSubscription<PlayerState>? _justState;
  StreamSubscription<Duration>? _justPos;
  StreamSubscription<bool>? _mpvPlaying;
  StreamSubscription<Duration>? _mpvPosition;
  StreamSubscription<Duration>? _mpvDuration;
  StreamSubscription<bool>? _mpvCompleted;
  StreamSubscription<String>? _mpvError;

  final _states = StreamController<PlayerState>.broadcast();
  final _positions = StreamController<Duration>.broadcast();

  bool _androidFile = false;
  bool _opening = false;
  bool _endSent = false;
  int _gen = 0;
  int _armedGen = -1;
  PlayerState _lastState = PlayerState(false, ProcessingState.idle);
  Duration _lastPosition = Duration.zero;
  Duration? _androidDuration;
  double _volume = 1;

  bool get playingAndroidFile => _androidFile;

  Stream<PlayerState> get playerStateStream {
    return Stream<PlayerState>.multi((listener) {
      listener.add(_lastState);
      final sub = _states.stream.listen(
        listener.add,
        onError: listener.addError,
        onDone: listener.close,
      );
      listener.onCancel = sub.cancel;
    });
  }

  Stream<Duration> get positionStream {
    return Stream<Duration>.multi((listener) {
      listener.add(_lastPosition);
      final sub = _positions.stream.listen(
        listener.add,
        onError: listener.addError,
        onDone: listener.close,
      );
      listener.onCancel = sub.cancel;
    });
  }

  Stream<bool> get shuffleModeEnabledStream =>
      justAudio.shuffleModeEnabledStream;

  Stream<LoopMode> get loopModeStream => justAudio.loopModeStream;

  Duration? get duration => _androidFile ? _androidDuration : justAudio.duration;

  Duration get position => _lastPosition;

  double get volume => _volume;

  Future<void> playAndroidFile(File file) async {
    final gen = ++_gen;
    _androidFile = true;
    _endSent = false;
    _armedGen = -1;
    _androidDuration = null;
    _lastPosition = Duration.zero;
    MediaKit.ensureInitialized();
    try {
      await justAudio.pause();
    } catch (_) {}

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    await session.setActive(true);

    final player = _mpv ??= Player(
      configuration: const PlayerConfiguration(
        vo: 'null',
        title: 'Music',
      ),
    );
    _listenMpv(player);

    _opening = true;
    try {
      await player.open(Media(file.absolute.uri.toString()), play: true);
    } finally {
      _opening = false;
    }
    if (gen != _gen) return;
    _armedGen = gen;
    try {
      await player.setVideoTrack(VideoTrack.no());
    } catch (_) {}
    await player.setVolume(_volume * 100);
    _localPlaying(true);
  }

  Future<void> stopAndroidFile() async {
    if (!_androidFile && _mpv == null) return;
    _gen++;
    _androidFile = false;
    _androidDuration = null;
    try {
      await _mpv?.stop();
    } catch (_) {}
  }

  Future<void> play() async {
    if (_androidFile) {
      await _mpv?.play();
      return;
    }
    await justAudio.play();
  }

  Future<void> pause() async {
    if (_androidFile) {
      await _mpv?.pause();
      return;
    }
    await justAudio.pause();
  }

  Future<void> seek(Duration position) async {
    if (_androidFile) {
      _endSent = false;
      await _mpv?.seek(position);
      return;
    }
    await justAudio.seek(position);
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    if (_androidFile) {
      await _mpv?.setVolume(_volume * 100);
    }
    try {
      await justAudio.setVolume(_volume);
    } catch (_) {}
  }

  void _listenMpv(Player player) {
    if (_mpvPlaying != null) return;
    _mpvPlaying = player.stream.playing.listen((playing) {
      if (!_androidFile) return;
      _localPlaying(playing);
    });
    _mpvPosition = player.stream.position.listen((position) {
      if (!_androidFile) return;
      _lastPosition = position;
      if (!_positions.isClosed) _positions.add(position);
    });
    _mpvDuration = player.stream.duration.listen((duration) {
      if (!_androidFile) return;
      _androidDuration = duration;
      if (!_positions.isClosed) _positions.add(_lastPosition);
    });
    _mpvCompleted = player.stream.completed.listen((done) {
      if (!done || !_androidFile || _endSent || _opening) return;
      if (_armedGen != _gen) return;
      final duration = _androidDuration;
      final tooEarly = _lastPosition < const Duration(milliseconds: 500) &&
          (duration == null || duration > const Duration(seconds: 2));
      if (tooEarly) return;
      _endSent = true;
      onAndroidEnded?.call();
    });
    _mpvError = player.stream.error.listen((message) {
      if (_opening || !_androidFile || message.trim().isEmpty) return;
      if (_lastPosition > const Duration(seconds: 1)) return;
      onAndroidError?.call(message);
    });
  }

  void _localPlaying(bool playing) {
    _lastState = PlayerState(playing, ProcessingState.ready);
    if (!_states.isClosed) _states.add(_lastState);
  }

  Future<void> dispose() async {
    _gen++;
    _androidFile = false;
    await _justState?.cancel();
    await _justPos?.cancel();
    await _mpvPlaying?.cancel();
    await _mpvPosition?.cancel();
    await _mpvDuration?.cancel();
    await _mpvCompleted?.cancel();
    await _mpvError?.cancel();
    await _mpv?.dispose();
    await justAudio.dispose();
    await _states.close();
    await _positions.close();
  }
}
