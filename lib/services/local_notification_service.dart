import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'app_navigation.dart';
import 'dart:convert';

/// Native OS notifications for this app. Used for foreground FCM message notifications and other local alerts, but kept generic (a plain
/// title/body `show()`) rather than message-specific so anything else
/// that wants a local notification later can reuse it instead of writing
/// its own plugin wiring.
///
/// IMPORTANT LIMITATION: this only fires while the app process is alive
/// (foreground or backgrounded-but-not-killed) — there's no
/// FCM/APNs/background-service piece here, so if the OS has fully killed
/// the app, notifications won't arrive until it's reopened, at which
/// Treat this as "live while the app's running," not "always-on push,"
/// unless a background handler is added for that feature.
class LocalNotificationService {
  LocalNotificationService._();
  static final instance = LocalNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const aiApprovalPayload = 'ai_approval';

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
      // Fires when a notification is tapped while the app process is
      // already alive (foreground or backgrounded) — the app-launched-
      // from-cold case is handled separately below, since this callback
      // never fires for that.
      onDidReceiveNotificationResponse: _onTap,
    );

    _initialized = true;

    // Cold start: the app was fully killed and the tap that's launching
    // it right now is what we'd otherwise want onDidReceiveNotificationResponse
    // for, but that callback only exists once the plugin's already
    // initialized — which it wasn't yet. This is reported here instead.
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      _handlePayload(launchDetails!.notificationResponse?.payload);
    }
  }

  /// Android 13+ treats notifications as a runtime permission — the
  /// plugin declares it in its own manifest merge, but still needs this
  /// explicit prompt at runtime, same as camera/location would.
  ///
  /// Deliberately NOT part of init(): this shows a system dialog, which
  /// needs a resumed Activity/attached window to display and return a
  /// result. init() is awaited in main() *before* runApp() — calling
  /// this there raced the native launch screen on real devices (OEM
  /// launch animations especially) and could hang forever waiting on an
  /// Activity state that hadn't arrived yet, which meant runApp() never
  /// ran and the app never got past its splash/logo. Call this instead
  /// from a post-frame callback once the widget tree is actually up.
  Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  void _onTap(NotificationResponse response) {
    _handlePayload(response.payload);
  }

  void _handlePayload(String? payload) {
    if (payload != null && payload.startsWith('{')) {
      try {
        final data = jsonDecode(payload);
        if (data is Map && data['type'] == 'ai_approval') {
          AppNavigation.goToAiApproval(data['id']?.toString());
          return;
        }
      } catch (_) {}
    }
    if (payload == aiApprovalPayload) {
      AppNavigation.goToAiApproval();
    }
  }

  Future<void> show({
    required int id,
    required String title,
    required String body,
    String channelId = 'z_general',
    String channelName = 'General',
    String? payload,
  }) async {
    if (!_initialized) await init();

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.show(id, title, body.isEmpty ? null : body, details, payload: payload);
  }

  /// Notification id must fit a 32-bit int on Android.
  static int idFor(String key) => key.hashCode & 0x7FFFFFFF;
}
