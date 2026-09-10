import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'inbox_bridge_service.dart';
import 'local_notification_service.dart';

@pragma('vm:entry-point')
Future<void> inboxFirebaseBackgroundHandler(RemoteMessage message) async {
  // The Inbox Worker sends an FCM notification payload. When the app is
  // backgrounded/terminated, Android/iOS displays that notification itself.
}

class InboxPushService {
  InboxPushService._();
  static final instance = InboxPushService._();

  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<String>? _tokenSub;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      final token = await messaging.getToken();
      if (token != null) {
        try {
          await InboxBridgeService.instance.registerDeviceToken(token);
        } catch (e) {
          debugPrint('Inbox FCM registration deferred: $e');
        }
      }

      _foregroundSub = FirebaseMessaging.onMessage.listen((message) {
        final notification = message.notification;
        if (notification == null) return;
        LocalNotificationService.instance.showMessage(
          messageId: message.messageId ?? DateTime.now().microsecondsSinceEpoch.toString(),
          senderLabel: notification.title ?? 'New message',
          text: notification.body ?? '',
        );
      });

      _tokenSub = messaging.onTokenRefresh.listen((newToken) async {
        try {
          await InboxBridgeService.instance.registerDeviceToken(newToken);
        } catch (e) {
          debugPrint('Inbox FCM token refresh deferred: $e');
        }
      });
    } catch (e) {
      // Missing Firebase client files should never prevent the owner from
      // signing in or reading Inbox history. Push becomes active once the
      // native Firebase config is added.
      debugPrint('Inbox FCM unavailable: $e');
    }
  }

  Future<void> stop() async {
    await _foregroundSub?.cancel();
    await _tokenSub?.cancel();
    _foregroundSub = null;
    _tokenSub = null;
    _started = false;
  }
}
