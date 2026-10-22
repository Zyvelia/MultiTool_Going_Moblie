import 'package:flutter/material.dart';
import 'vault_screen.dart';
import 'library_screen.dart';
import 'notes_screen.dart';
import 'reminders_screen.dart';
import 'clock_screen.dart';
import 'games_screen.dart';
import 'yt_screen.dart';
import 'quick_send_screen.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';
import 'stream_service_screen.dart';
import 'steps_screen.dart';
import '../services/settings_service.dart';
import '../services/app_navigation.dart';
import '../services/home_tabs.dart';
import 'ai_approvals_screen.dart';

/// Lets code outside the widget tree (notably LocalNotificationService,
/// which fires from a plugin callback with no BuildContext of its own)
/// reach the live HomeShell instance to switch tabs. Attached via
/// `HomeShell(key: homeShellKey)` in main.dart.
final homeShellKey = GlobalKey<HomeShellState>();
final libraryScreenKey = GlobalKey<LibraryScreenState>();

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> {
  int _index = 0;
  late final PageController _pageController;
  final _settings = SettingsService();
  String? _hostname;
  bool _checked = false;

  /// Steps touches pedometer + Health Connect; defer until the tab is opened
  /// so cold start stays safe on Android 11 / Samsung (Galaxy S20+).
  bool _stepsTabBuilt = false;

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

    // A notification tap that launched the app from cold gets handled by
    // LocalNotificationService before this widget exists, so it stashes
    // the target tab in AppNavigation instead of calling us directly.
    // Claim it now that we're up, once the first frame after this build
    // has actually gone out (jumping pages mid-build throws).
    final pendingTab = AppNavigation.consumePendingTabIndex();
    final pendingApproval = AppNavigation.consumePendingApprovalId();
    if (pendingApproval != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openAiApproval(pendingApproval);
      });
    }

    if (pendingTab != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) selectTab(pendingTab);
        if (pendingTab == HomeTabs.music) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            libraryScreenKey.currentState?.handleExternalOpen();
          });
        }
      });
    }
  }

  /// Public entry point for switching tabs from outside this State —
  /// used by AppNavigation to deep-link in from a tapped notification.
  void selectTab(int i) {
    _onDestinationSelected(i);
    if (i == HomeTabs.music) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        libraryScreenKey.currentState?.handleExternalOpen();
      });
    }
  }

  void openAiApproval([String? approvalId]) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AiApprovalsScreen(requestedId: approvalId)));
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
    if (i == HomeTabs.steps) _stepsTabBuilt = true;
    setState(() => _index = i);
    // Guards a narrow edge case unique to the notification deep-link
    // path: if a tap resolves before the PC hostname is set up, build()
    // is still showing the setup prompt instead of the PageView, so
    // there's no client to animate yet. _index is already updated above,
    // so the right tab shows as soon as the PageView does exist.
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        i,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  // Fires continuously while dragging (page value moves fractionally
  // with the finger) and on settle, so the bottom nav's highlighted
  // tab tracks the swipe in real time instead of jumping at the end.
  void _onPageChanged(int i) {
    setState(() {
      _index = i;
      if (i == HomeTabs.steps) _stepsTabBuilt = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Each screen is wrapped in _KeepAlive so swiping away and back
    // (or tapping between tabs) doesn't reset scroll position, text
    // fields, or in-flight loads — same persistence IndexedStack gave
    // before, just now living inside a swipeable PageView.
    final screens = [
      const _KeepAlive(child: VaultScreen()),
      _KeepAlive(child: LibraryScreen(key: libraryScreenKey)),
      const _KeepAlive(child: NotesScreen()),
      const _KeepAlive(child: RemindersScreen()),
      const _KeepAlive(child: ClockScreen()),
      _KeepAlive(
        child: _stepsTabBuilt
            ? const StepsScreen()
            : const SizedBox.shrink(),
      ),
      const _KeepAlive(child: GamesScreen()),
      const _KeepAlive(child: YtScreen()),
      const _KeepAlive(child: QuickSendScreen()),
      const _KeepAlive(child: ChatScreen()),
      const _KeepAlive(child: StreamServiceScreen()),
      const _KeepAlive(child: SettingsScreen()),
    ];

    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.lock), label: 'Vault'),
          NavigationDestination(icon: Icon(Icons.music_note), label: 'Music'),
          NavigationDestination(icon: Icon(Icons.notes), label: 'Notes'),
          NavigationDestination(
            icon: Icon(Icons.alarm_outlined),
            label: 'Reminders',
          ),
          NavigationDestination(
            icon: Icon(Icons.access_time),
            label: 'Clock',
          ),
          NavigationDestination(
            icon: Icon(Icons.directions_walk),
            label: 'Steps',
          ),
          NavigationDestination(icon: Icon(Icons.sports_esports), label: 'Games'),
          NavigationDestination(icon: Icon(Icons.download), label: 'YT'),
          NavigationDestination(icon: Icon(Icons.send), label: 'Send'),
          NavigationDestination(icon: Icon(Icons.smart_toy_outlined), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.desktop_windows_outlined), label: 'PC'),
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
