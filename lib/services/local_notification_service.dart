import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/mirrored_notification.dart';

/// Turns a [MirroredNotification] into a real native notification on the
/// phone. This app had zero notification plumbing before this feature —
/// there's no existing implementation being extended here.
///
/// IMPORTANT LIMITATION: this only fires while the app process is alive
/// (foreground or backgrounded-but-not-killed) — there's no
/// FCM/APNs/background-service piece in this MVP, so if the OS has fully
/// killed the app, mirrored notifications won't arrive until it's
/// reopened, at which point the PC-side backlog (see web_server.py's
/// _Broker, and getHistory()) fills in what was missed. Treat this as
/// "live while the app's running," not "always-on push," until a
/// background-service follow-up is built.
class LocalNotificationService {
  LocalNotificationService._();
  static final instance = LocalNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    // Android 13+ treats notifications as a runtime permission — the
    // plugin declares it in its own manifest merge, but still needs this
    // explicit prompt at runtime, same as camera/location would.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  Future<void> showMirrored(MirroredNotification n) async {
    if (!_initialized) await init();

    const androidDetails = AndroidNotificationDetails(
      'z_connect_mirrored',
      'Mirrored PC Notifications',
      channelDescription: 'Notifications forwarded from your PC via Z Connect',
      importance: Importance.high,
      priority: Priority.high,
      groupKey: 'z_connect_mirrored_group',
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    // Small "from PC" marker so it's never mistaken for a notification
    // the app itself generated, per spec.
    final title = '💻 ${n.appName}';
    final body = n.title.isNotEmpty && n.body.isNotEmpty
        ? '${n.title}\n${n.body}'
        : (n.title.isNotEmpty ? n.title : n.body);

    // Notification ids on Android must fit a 32-bit int — the PC's
    // WinRT ids are uint32 already, but hash defensively in case a
    // future source produces something larger.
    final localId = n.id & 0x7FFFFFFF;

    await _plugin.show(localId, title, body.isEmpty ? null : body, details);
  }
}
