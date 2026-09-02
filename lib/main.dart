import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'screens/home_shell.dart';
import 'services/local_notification_service.dart';
import 'theme/app_theme.dart';

/// App-wide navigator handle. Not used directly for the notification
/// deep-link (switching tabs happens through [homeShellKey] instead,
/// since HomeShell's tabs are a PageView, not routes) but kept available
/// for any future case — pushing a screen from a background callback,
/// deep links from outside the app, etc. — that needs a BuildContext
/// with no widget nearby to source one from.
final navigatorKey = GlobalKey<NavigatorState>();

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
  // Initialized here (rather than left to lazily init on first use, as
  // before) so a cold start launched by tapping a notification is caught
  // reliably — that check happens inside init() and needs to run before
  // HomeShell claims it, regardless of which tab the user lands on first.
  // NOTE: this only does plugin registration + the cold-start launch
  // check now, not the runtime permission dialog — see
  // LocalNotificationService.requestPermission() for why that's
  // deliberately deferred to after the first frame.
  await LocalNotificationService.instance.init();
  runApp(const MultiToolRemoteApp());
  // The Android 13+ notification permission prompt needs a resumed
  // Activity to actually display and return a result. Requesting it here
  // (pre-runApp) used to hang the app on real devices before it ever got
  // past the launch screen — see requestPermission()'s doc comment.
  // addPostFrameCallback guarantees the first frame is already on screen
  // before this fires.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    LocalNotificationService.instance.requestPermission();
  });
}

class MultiToolRemoteApp extends StatelessWidget {
  const MultiToolRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: "Zs Multi Tool Remote",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: HomeShell(key: homeShellKey),
    );
  }
}
