import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'screens/home_shell.dart';

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
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1115),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4EA1FF),
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF151922),
          elevation: 0,
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF1B2030),
          elevation: 0,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFF151922),
          indicatorColor: Color(0xFF23304a),
        ),
      ),
      home: const HomeShell(),
    );
  }
}
