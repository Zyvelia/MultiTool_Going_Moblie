import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'app_navigation.dart';

Future<void>? _initFuture;

/// [JustAudioBackground] swaps in its platform plugin before it assigns the
/// audio handler. Creating or playing an [AudioPlayer] in that gap throws
/// `LateInitializationError` on `_audioHandler`.
Future<void> ensureAudioBackground() {
  final existing = _initFuture;
  if (existing != null) return existing;
  final started = _start();
  _initFuture = started;
  return started;
}

Future<void> _start() async {
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.zsmultitool.multi_tool_remote.audio',
      androidNotificationChannelName: 'Music playback',
      androidNotificationOngoing: true,
      androidNotificationClickStartsActivity: true,
      androidResumeOnClick: true,
    );
    AudioService.notificationClicked.listen((clicked) {
      if (clicked) {
        AppNavigation.goToMusic(openNowPlaying: true);
      }
    });
  } catch (e, st) {
    _initFuture = null;
    debugPrint('JustAudioBackground.init failed: $e\n$st');
    rethrow;
  }
}
