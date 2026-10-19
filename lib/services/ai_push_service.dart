import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'ai_approval_service.dart';
import 'app_navigation.dart';
import 'local_notification_service.dart';
import 'settings_service.dart';

@pragma('vm:entry-point')
Future<void> aiFirebaseBackgroundHandler(RemoteMessage message) async {
  // FCM may display notification payloads while the app is backgrounded.
  // AI approval handling is wired in [AiPushService] when the app is alive.
}

/// Push channel dedicated to the PC AI approval system.
///
/// Uses the phone's normal OS push notification tray through FCM, while the
/// approval API remains a separate HTTP API on the PC AI server.
class AiPushService {
  AiPushService._();
  static final instance = AiPushService._();

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

      final initial = await messaging.getInitialMessage();
      if (initial != null) _routeMessage(initial);

      _tokenSub = messaging.onTokenRefresh.listen((newToken) async {
        await _registerToken(newToken);
      });
    } catch (e) {
      debugPrint('AI push notifications unavailable: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      final settings = SettingsService();
      final base = await settings.baseUrl('chat');
      if (base == null || base.isEmpty) return;

      final code = await settings.getAccessCode('chat');
      final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
      await AiApprovalService(base, accessCode: code).registerFcmToken(
        token,
        platform: platform,
      );
    } catch (e) {
      // Registration is retried naturally on token refresh/app restart.
      debugPrint('AI push token registration deferred: $e');
    }
  }

  void _handleForeground(RemoteMessage message) {
    if (message.data['type']?.toString() != 'ai_approval') return;

    final id = message.data['approval_id']?.toString() ??
        message.data['id']?.toString() ??
        '';

    LocalNotificationService.instance.show(
      id: LocalNotificationService.idFor(id.isEmpty ? DateTime.now().microsecondsSinceEpoch.toString() : id),
      title: message.notification?.title ?? 'AI approval required',
      body: message.notification?.body ?? 'The AI is waiting for your approval.',
      channelId: 'z_ai_approvals',
      channelName: 'AI approvals',
      payload: jsonEncode({'type': 'ai_approval', 'id': id}),
    );
  }

  void _routeMessage(RemoteMessage message) {
    if (message.data['type']?.toString() != 'ai_approval') return;
    AppNavigation.goToAiApproval(
      message.data['approval_id']?.toString() ?? message.data['id']?.toString(),
    );
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
