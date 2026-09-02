import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'app_navigation.dart';

/// Native OS notifications for this app. Currently only used for incoming
/// chat messages (see messages_screen.dart), but kept generic (a plain
/// title/body `show()`) rather than message-specific so anything else
/// that wants a local notification later can reuse it instead of writing
/// its own plugin wiring.
///
/// IMPORTANT LIMITATION: this only fires while the app process is alive
/// (foreground or backgrounded-but-not-killed) — there's no
/// FCM/APNs/background-service piece here, so if the OS has fully killed
/// the app, notifications won't arrive until it's reopened, at which
/// point MessagingApiService's fetchHistory() catch-up fills in whatever
/// was missed. Treat this as "live while the app's running," not
/// "always-on push," until a background-service follow-up is built.
class LocalNotificationService {
  LocalNotificationService._();
  static final instance = LocalNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Payload tag for message notifications — checked on tap so we only
  /// deep-link into Messages for the notification type that actually
  /// means something there, not any future notification kind that
  /// reuses this same show() plumbing.
  static const messagePayload = 'messages';

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

    // Android 13+ treats notifications as a runtime permission — the
    // plugin declares it in its own manifest merge, but still needs this
    // explicit prompt at runtime, same as camera/location would.
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

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

  void _onTap(NotificationResponse response) {
    _handlePayload(response.payload);
  }

  void _handlePayload(String? payload) {
    switch (payload) {
      case messagePayload:
        AppNavigation.goToMessages();
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

  /// Notification id must fit a 32-bit int on Android — message ids are
  /// arbitrary strings (uuid4 hex from the desktop, or our own
  /// Message.newId() hex), so hash defensively rather than assuming any
  /// particular format.
  static int idFor(String messageId) => messageId.hashCode & 0x7FFFFFFF;

  Future<void> showMessage({
    required String messageId,
    required String senderLabel,
    required String text,
  }) {
    return show(
      id: idFor(messageId),
      title: senderLabel,
      body: text,
      channelId: 'z_messages',
      channelName: 'Messages',
      payload: messagePayload,
    );
  }
}
