import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Registers the background audio service + lock-screen/notification
  // controls. Must happen before any AudioPlayer is created.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.zsmultitool.music_remote.audio',
    androidNotificationChannelName: 'Music playback',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
  );
  runApp(const MusicRemoteApp());
}

class MusicRemoteApp extends StatelessWidget {
  const MusicRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zs Music Remote',
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
      ),
      home: const StartupScreen(),
    );
  }
}

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  final _settings = SettingsService();
  bool _checked = false;
  String? _serverUrl;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final url = await _settings.getServerUrl();
    setState(() {
      _serverUrl = url;
      _checked = true;
    });
  }

  Future<void> _promptForServer() async {
    final url = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const SettingsScreen(initialUrl: null)),
    );
    if (url != null && url.isNotEmpty) {
      setState(() => _serverUrl = url);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_serverUrl == null || _serverUrl!.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _promptForServer());
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Set up your server to get started…',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ),
      );
    }
    return LibraryScreen(serverUrl: _serverUrl!);
  }
}
