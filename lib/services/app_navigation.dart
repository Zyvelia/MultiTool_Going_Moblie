import 'package:flutter/widgets.dart';
import '../screens/home_shell.dart';
import '../screens/ai_approvals_screen.dart';

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
