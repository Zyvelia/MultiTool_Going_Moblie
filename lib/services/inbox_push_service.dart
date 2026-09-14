import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'inbox_bridge_service.dart';
import 'local_notification_service.dart';
import 'app_navigation.dart';
import 'ai_approval_service.dart';
import 'settings_service.dart';

@pragma('vm:entry-point')
Future<void> inboxFirebaseBackgroundHandler(RemoteMessage message) async {
  // Notification payloads are displayed by the OS while the app is in the
  // background/terminated. Tap routing is handled by getInitialMessage() /
  // onMessageOpenedApp() in start().
}

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

      _foregroundSub = FirebaseMessaging.onMessage.listen((message) {
        _handleForeground(message);
      });

      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _routeMessage(message);
      });

      // Handles a notification tap that launched the app from a fully cold
      // state. This is separate from onMessageOpenedApp.
      final initial = await messaging.getInitialMessage();
      if (initial != null) _routeMessage(initial);

      _tokenSub = messaging.onTokenRefresh.listen((newToken) async {
        await _registerToken(newToken);
      });
    } catch (e) {
      debugPrint('Inbox/AI FCM unavailable: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      // Existing FCM registration used by Inbox/Cloudflare stays intact.
      await InboxBridgeService.instance.registerDeviceToken(token);
    } catch (e) {
      debugPrint('Inbox FCM registration deferred: $e');
    }

    // Also register the same token with the PC AI when its approval endpoint
    // exists. Older AI builds return 404 and are left untouched.
    try {
      final settings = SettingsService();
      final base = await settings.baseUrl('chat');
      if (base != null) {
        final code = await settings.getAccessCode('chat');
        final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
        await AiApprovalService(base, accessCode: code).registerFcmToken(
          token,
          platform: platform,
        );
      }
    } catch (e) {
      debugPrint('AI FCM registration deferred: $e');
    }
  }

  void _handleForeground(RemoteMessage message) {
    final type = message.data['type']?.toString();
    if (type == 'ai_approval') {
      final id = message.data['approval_id']?.toString() ?? message.data['id']?.toString();
      LocalNotificationService.instance.show(
        id: LocalNotificationService.idFor(id ?? DateTime.now().microsecondsSinceEpoch.toString()),
        title: message.notification?.title ?? 'AI approval required',
        body: message.notification?.body ?? 'The AI is waiting for your approval.',
        channelId: 'z_ai_approvals',
        channelName: 'AI approvals',
        payload: jsonEncode({'type': 'ai_approval', 'id': id ?? ''}),
      );
      return;
    }

    final notification = message.notification;
    if (notification == null) return;
    LocalNotificationService.instance.showMessage(
      messageId: message.messageId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      senderLabel: notification.title ?? 'New message',
      text: notification.body ?? '',
    );
  }

  void _routeMessage(RemoteMessage message) {
    final type = message.data['type']?.toString();
    if (type == 'ai_approval') {
      AppNavigation.goToAiApproval(
        message.data['approval_id']?.toString() ?? message.data['id']?.toString(),
      );
      return;
    }
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
