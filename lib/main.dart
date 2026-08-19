import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'screens/home_shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Wires the MediaItem tags set on each track in LibraryScreen into the
  // OS-level now-playing session — this is what makes playback show up on
  // the lock screen / Control Center / notification, and what keeps it
  // registered as background audio so iOS doesn't suspend it when the app
  // isn't in the foreground.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.zsmultitool.multi_tool_remote.audio',
    androidNotificationChannelName: 'Music playback',
    androidNotificationOngoing: true,
  );
  runApp(const MultiToolRemoteApp());
}

class MultiToolRemoteApp extends StatelessWidget {
  const MultiToolRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Zs Multi Tool Remote",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const HomeShell(),
    );
  }
}
