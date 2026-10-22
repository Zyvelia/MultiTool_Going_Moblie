import 'package:flutter/widgets.dart';

import '../screens/ai_approvals_screen.dart';
import '../screens/home_shell.dart';
import 'home_tabs.dart';

/// Bridges taps on OS-level notifications back into in-app navigation.
///
/// LocalNotificationService's tap callback fires from the
/// flutter_local_notifications plugin, outside any widget's BuildContext,
/// so it can't just call Navigator.of(context) or reach HomeShell's state
/// directly. This is the shared handle both sides use instead: main.dart
/// attaches `homeShellKey` to the live HomeShell, and
class AppNavigation {
  AppNavigation._();

  /// Set when a notification tap is handled before HomeShell has mounted
  /// yet — a cold start, where tapping the notification is what launches
  /// the app in the first place. HomeShell claims this via
  /// [consumePendingTabIndex] once it's up.
  static int? _pendingTabIndex;
  static String? _pendingApprovalId;
  static bool _pendingOpenNowPlaying = false;

  static void goToReminders() => _goToTab(HomeTabs.reminders);

  static void goToClock() => _goToTab(HomeTabs.clock);

  static void goToSteps() => _goToTab(HomeTabs.steps);

  /// Music tab; optionally open the now-playing sheet (e.g. media notification tap).
  static void goToMusic({bool openNowPlaying = false}) {
    if (openNowPlaying) _pendingOpenNowPlaying = true;
    _goToTab(HomeTabs.music);
  }

  static bool get pendingOpenNowPlaying => _pendingOpenNowPlaying;

  static void clearPendingOpenNowPlaying() {
    _pendingOpenNowPlaying = false;
  }

  static bool consumePendingOpenNowPlaying() {
    final v = _pendingOpenNowPlaying;
    _pendingOpenNowPlaying = false;
    return v;
  }

  static void goToAiApproval([String? approvalId]) {
    final state = homeShellKey.currentState;
    if (state != null) {
      state.openAiApproval(approvalId);
    } else {
      _pendingApprovalId = approvalId;
    }
  }

  static String? consumePendingApprovalId() {
    final id = _pendingApprovalId;
    _pendingApprovalId = null;
    return id;
  }

  static void _goToTab(int index) {
    final state = homeShellKey.currentState;
    if (state != null) {
      state.selectTab(index);
    } else {
      _pendingTabIndex = index;
    }
  }

  /// Called once by HomeShell after its own startup (hostname check,
  /// first frame) completes. Returns null on every call after the first
  /// pending index is claimed, or if there wasn't one.
  static int? consumePendingTabIndex() {
    final index = _pendingTabIndex;
    _pendingTabIndex = null;
    return index;
  }
}
