import 'package:flutter/material.dart';
import 'vault_screen.dart';
import 'library_screen.dart';
import 'notes_screen.dart';
import 'games_screen.dart';
import 'soundboard_screen.dart';
import 'yt_screen.dart';
import 'quick_send_screen.dart';
import 'settings_screen.dart';
import '../services/settings_service.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  late final PageController _pageController;
  final _settings = SettingsService();
  String? _hostname;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _index);
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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

  // Tapping a destination animates the PageView there — the swipe
  // gesture and the bottom nav stay in sync either way you navigate.
  void _onDestinationSelected(int i) {
    setState(() => _index = i);
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  // Fires continuously while dragging (page value moves fractionally
  // with the finger) and on settle, so the bottom nav's highlighted
  // tab tracks the swipe in real time instead of jumping at the end.
  void _onPageChanged(int i) {
    setState(() => _index = i);
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

    // Each screen is wrapped in _KeepAlive so swiping away and back
    // (or tapping between tabs) doesn't reset scroll position, text
    // fields, or in-flight loads — same persistence IndexedStack gave
    // before, just now living inside a swipeable PageView.
    final screens = const [
      _KeepAlive(child: VaultScreen()),
      _KeepAlive(child: LibraryScreen()),
      _KeepAlive(child: NotesScreen()),
      _KeepAlive(child: GamesScreen()),
      _KeepAlive(child: SoundboardScreen()),
      _KeepAlive(child: YtScreen()),
      _KeepAlive(child: QuickSendScreen()),
      _KeepAlive(child: SettingsScreen()),
    ];

    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.lock), label: 'Vault'),
          NavigationDestination(icon: Icon(Icons.music_note), label: 'Music'),
          NavigationDestination(icon: Icon(Icons.notes), label: 'Notes'),
          NavigationDestination(icon: Icon(Icons.sports_esports), label: 'Games'),
          NavigationDestination(icon: Icon(Icons.volume_up), label: 'Sounds'),
          NavigationDestination(icon: Icon(Icons.download), label: 'YT'),
          NavigationDestination(icon: Icon(Icons.send), label: 'Send'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

/// Keeps [child]'s state alive once built, even while it's off-screen
/// in the PageView. Without this, PageView disposes pages that scroll
/// out of the viewport and rebuilds them from scratch when you swipe
/// back — losing scroll position, loaded data, and in-progress input.
class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
