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
import '../services/settings_service.dart';
import '../services/app_navigation.dart';
import '../services/home_tabs.dart';
import 'ai_approvals_screen.dart';
import 'home_catalog.dart';

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
  /// Null while Home is showing. A [HomeTabs] index while a tool is open.
  int? _open;
  final _visited = <int>{};
  final _settings = SettingsService();
  bool _checked = false;

  bool get toolIsOpen => _open != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _settings.getHostname();
    if (!mounted) return;
    setState(() => _checked = true);

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

  /// Public entry point for opening a tool from outside this State —
  /// used by AppNavigation to deep-link in from a tapped notification.
  void selectTab(int i) {
    setState(() {
      _visited.add(i);
      _open = i;
    });
    if (i == HomeTabs.music) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        libraryScreenKey.currentState?.handleExternalOpen();
      });
    }
  }

  void closeTool() {
    if (_open == null) return;
    setState(() => _open = null);
  }

  void openAiApproval([String? approvalId]) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AiApprovalsScreen(requestedId: approvalId)));
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // A tool stays mounted after the first open, so leaving Music or Notes
    // and coming back does not throw away playback, scroll, or a draft.
    final screens = <Widget>[
      const VaultScreen(),
      LibraryScreen(key: libraryScreenKey),
      const NotesScreen(),
      const RemindersScreen(),
      const ClockScreen(),
      const GamesScreen(),
      const YtScreen(),
      const QuickSendScreen(),
      const ChatScreen(),
      const StreamServiceScreen(),
      const SettingsScreen(),
    ];
    final kept = <Widget>[
      for (var i = 0; i < screens.length; i++)
        _visited.contains(i) ? screens[i] : const SizedBox.shrink(),
    ];

    return PopScope(
      canPop: _open == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) closeTool();
      },
      child: IndexedStack(
        index: _open == null ? 0 : 1,
        children: [
          HomeCatalog(
            onOpen: selectTab,
            onSettings: () => selectTab(HomeTabs.settings),
          ),
          IndexedStack(
            index: _open ?? 0,
            children: kept,
          ),
        ],
      ),
    );
  }
}
