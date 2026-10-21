import 'package:audioplayers/audioplayers.dart';

import 'alarm_sound_catalog.dart';

class AlarmSoundPlayer {
  AlarmSoundPlayer._();
  static final instance = AlarmSoundPlayer._();

  final _player = AudioPlayer();
  bool _playing = false;

  Future<void> preview(String soundRef) async {
    await stop();
    final path = await AlarmSoundCatalog.instance.resolvePlayablePath(soundRef);
    if (path == null) return;
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.setVolume(1.0);
    await _player.play(DeviceFileSource(path));
    _playing = true;
    Future.delayed(const Duration(seconds: 3), () {
      if (_playing) stop();
    });
  }

  Future<void> startAlarmLoop(String soundRef) async {
    await stop();
    final path = await AlarmSoundCatalog.instance.resolvePlayablePath(soundRef);
    if (path == null) return;
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(1.0);
    await _player.play(DeviceFileSource(path));
    _playing = true;
  }

  Future<void> stop() async {
    _playing = false;
    await _player.stop();
  }
}
