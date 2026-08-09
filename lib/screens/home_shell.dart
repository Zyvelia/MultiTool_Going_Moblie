import 'package:flutter/material.dart';
import 'vault_screen.dart';
import 'library_screen.dart';
import 'games_screen.dart';
import 'soundboard_screen.dart';
import 'yt_screen.dart';
import 'settings_screen.dart';
import '../services/settings_service.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _settings = SettingsService();
  String? _hostname;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final host = await _settings.getHostname();
    setState(() {
      _hostname = host;
      _checked = true;
    });
  }

  Future<void> _promptForHostname() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_hostname == null || _hostname!.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _promptForHostname());
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Set up your PC\'s Tailscale hostname to get started…',
              style: TextStyle(color: Colors.white54),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final screens = [
      const VaultScreen(),
      const LibraryScreen(),
      const GamesScreen(),
      const SoundboardScreen(),
      const YtScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.lock), label: 'Vault'),
          NavigationDestination(icon: Icon(Icons.music_note), label: 'Music'),
          NavigationDestination(icon: Icon(Icons.sports_esports), label: 'Games'),
          NavigationDestination(icon: Icon(Icons.volume_up), label: 'Sounds'),
          NavigationDestination(icon: Icon(Icons.download), label: 'YT'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
