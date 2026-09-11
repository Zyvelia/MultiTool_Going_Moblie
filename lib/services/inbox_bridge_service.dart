import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/inbox_message.dart';

/// Bridge to Inbox Worker.
///
/// Better Auth stores the session in an httpOnly cookie. Flutter cannot read
/// that cookie directly, so API calls run from the worker's own WebView
/// origin, where the WebView automatically supplies the session cookie.
class InboxBridgeService {
  InboxBridgeService._();
  static final instance = InboxBridgeService._();

  static const workerUrl = 'https://inbox-worker.itszyvelia.workers.dev';

  WebViewController? _controller;
  Completer<void>? _pageReady;
  Future<WebViewController>? _creatingController;

  /// Kept for compatibility with older callers. The Inbox WebView is owned
  /// by the Messages screen and remains mounted so the authenticated WebView
  /// session can be used for API requests after login.
  void invalidateController() {
    // Intentionally do nothing.
    // Better Auth's httpOnly session cookie is only directly available to the
    // WebView. Keeping the same controller/session is what lets native Flutter
    /// fetch the inbox without displaying the Worker inbox website.
  }

  Future<WebViewController> ensureController() async {
    final existing = _controller;
    if (existing != null) return existing;

    final pending = _creatingController;
    if (pending != null) return pending;

    final future = createController();
    _creatingController = future;
    try {
      return await future;
    } finally {
      if (identical(_creatingController, future)) {
        _creatingController = null;
      }
    }
  }

  Future<WebViewController> createController({
    void Function(String url)? onNavigation,
    void Function(String error)? onError,
  }) async {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            final ready = _pageReady;
            if (ready != null && !ready.isCompleted) ready.complete();
          },
          onNavigationRequest: (request) {
            onNavigation?.call(request.url);
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) => onError?.call(error.description),
        ),
      );

    _controller = controller;
    _pageReady = Completer<void>();
    await controller.loadRequest(Uri.parse(workerUrl));
    return controller;
  }

  Future<void> waitForPage() async {
    final ready = _pageReady;
    if (ready != null && !ready.isCompleted) {
      try {
        await ready.future.timeout(const Duration(seconds: 20));
      } catch (_) {}
    }
  }

  Future<dynamic> _runJson(String script) async {
    final controller = await ensureController();

    final raw = await controller.runJavaScriptReturningResult(script);
    var text = raw.toString().trim();

    // Android/iOS WebViews may return a JSON string wrapped in another
    // JSON string. Peel those layers before decoding the API response.
    for (var i = 0; i < 2; i++) {
      if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
        try {
          final decoded = jsonDecode(text);
          if (decoded is String) {
            text = decoded.trim();
            continue;
          }
          return decoded;
        } catch (_) {}
      }
      break;
    }

    if (text == 'null' || text.isEmpty) return null;
    return jsonDecode(text);
  }

  /// Returns the actual /api/me response body.
  ///
  /// The JavaScript bridge wraps HTTP responses as {status, data}. Keep that
  /// transport wrapper private so callers receive the same shape documented
  /// by the Worker: {user, isOwner}.
  Future<Map<String, dynamic>> me() async {
    await ensureController();
    await waitForPage();

    final result = await _runJson('''
(async () => {
  const r = await fetch(${jsonEncode('$workerUrl/api/me')}, {
    method: 'GET',
    credentials: 'include',
    cache: 'no-store'
  });
  let data = null;
  try {
    data = await r.json();
  } catch (_) {}
  return JSON.stringify({status: r.status, data: data});
})()
''');

    final envelope = Map<String, dynamic>.from(result as Map);
    final status = envelope['status'];
    final body = envelope['data'];

    if (status != 200) {
      throw StateError('Inbox session check failed ($status).');
    }
    if (body is! Map) {
      throw StateError('Inbox session response was invalid.');
    }

    return Map<String, dynamic>.from(body);
  }

  Future<Map<String, dynamic>> sessionInfo() async {
    return me();
  }

  Future<void> ensureOwner() async {
    final data = await me();
    if (data['user'] == null || data['isOwner'] != true) {
      throw StateError('This account is not the Inbox owner.');
    }
  }

  Future<void> registerDeviceToken(String token) async {
    await ensureOwner();
    final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
    final payload = jsonEncode({'token': token, 'platform': platform});
    final result = await _runJson('''
(async () => {
  const r = await fetch(${jsonEncode('$workerUrl/api/device-token')}, {
    method: 'POST',
    credentials: 'include',
    headers: {'Content-Type': 'application/json'},
    body: ${jsonEncode(payload)}
  });
  return JSON.stringify({status: r.status, text: await r.text()});
})()
''');
    final status = (result as Map)['status'];
    if (status != 200) {
      throw StateError('Device registration failed ($status).');
    }
  }

  Future<List<InboxMessage>> fetchMessages({int? since}) async {
    await ensureOwner();
    final query = since == null ? '' : '?since=$since';
    final result = await _runJson('''
(async () => {
  const r = await fetch(${jsonEncode('$workerUrl/api/messages$query')}, {
    method: 'GET',
    credentials: 'include',
    cache: 'no-store'
  });
  return JSON.stringify({status: r.status, data: await r.json()});
})()
''');
    final map = Map<String, dynamic>.from(result as Map);
    if (map['status'] != 200) {
      throw StateError('Could not load messages (${map['status']}).');
    }
    final data = Map<String, dynamic>.from(map['data'] as Map);
    return (data['messages'] as List<dynamic>? ?? const [])
        .map((item) => InboxMessage.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }
}
