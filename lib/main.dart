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
  // Both of these used to run pre-runApp and could hang cold start on
  // real devices (confirmed on a Galaxy A16 — logo screen never
  // cleared, while iOS was unaffected since it has no equivalent
  // restriction):
  //
  // - JustAudioBackground.init() with androidNotificationOngoing:true
  //   spins up a foreground media session. Android 12+ (and Samsung's
  //   One UI especially) can block/stall starting a foreground service
  //   while the app has no visible Activity yet, which is exactly the
  //   state pre-runApp() — so the init future could just never resolve.
  // - The Android 13+ notification permission prompt needs a resumed
  //   Activity to display and return a result; requesting it pre-runApp
  //   raced the native launch screen and could hang the same way.
  //
  // addPostFrameCallback guarantees the first frame is already on
  // screen (engine attached, Activity resumed) before either fires, so
  // cold start is never blocked on them. Wires the MediaItem tags set
  // on each track in LibraryScreen into the OS-level now-playing
  // session once it does run — this is what makes playback show up on
  // the lock screen / Control Center / notification, and what keeps it
  // registered as background audio so iOS doesn't suspend it when the
  // app isn't in the foreground.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.zsmultitool.multi_tool_remote.audio',
      androidNotificationChannelName: 'Music playback',
      androidNotificationOngoing: true,
    );
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
