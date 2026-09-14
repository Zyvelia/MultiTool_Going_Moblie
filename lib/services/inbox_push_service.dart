import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'inbox_bridge_service.dart';
import 'local_notification_service.dart';
import 'app_navigation.dart';

@pragma('vm:entry-point')
Future<void> inboxFirebaseBackgroundHandler(RemoteMessage message) async {
  // FCM notification payloads are displayed by the OS while the app is in
  // the background/terminated. AI approvals use the same OS notification
  // mechanism, but their handling is isolated in AiPushService.
}

/// Push handling for the existing Inbox only.
///
/// AI approvals deliberately do not depend on this service. They have their
/// own push listener/registration in AiPushService.
class InboxPushService {
  InboxPushService._();
  static final instance = InboxPushService._();

  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<String>? _tokenSub;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      final token = await messaging.getToken();
      if (token != null) await _registerToken(token);

      _foregroundSub = FirebaseMessaging.onMessage.listen(_handleForeground);
      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_routeMessage);

      _tokenSub = messaging.onTokenRefresh.listen((newToken) async {
        await _registerToken(newToken);
      });
    } catch (e) {
      debugPrint('Inbox push notifications unavailable: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      await InboxBridgeService.instance.registerDeviceToken(token);
    } catch (e) {
      debugPrint('Inbox FCM registration deferred: $e');
    }
  }

  void _handleForeground(RemoteMessage message) {
    if (message.data['type']?.toString() == 'ai_approval') return;

    final notification = message.notification;
    if (notification == null) return;
    LocalNotificationService.instance.showMessage(
      messageId: message.messageId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      senderLabel: notification.title ?? 'New message',
      text: notification.body ?? '',
    );
  }

  void _routeMessage(RemoteMessage message) {
    if (message.data['type']?.toString() == 'ai_approval') return;
    if (message.data['type'] == 'inbox_message' || message.notification != null) {
      AppNavigation.goToMessages();
    }
  }

  Future<void> stop() async {
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    await _tokenSub?.cancel();
    _foregroundSub = null;
    _openedSub = null;
    _tokenSub = null;
    _started = false;
  }
}
