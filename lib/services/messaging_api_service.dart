import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'device_trust_service.dart';
import 'trusted_http.dart';
import 'user_facing_error.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import '../models/message.dart';

/// Talks to modules/Productivity/Messaging/web_server.py on the desktop
/// over a persistent WebSocket (wss://host:8452/ws) rather than polling —
/// a push-on-arrival requirement the other modules' request/response
/// ApiServices don't fit.
///
/// Reconnects automatically on drop (Tailscale hiccup, PC sleep/wake)
/// with capped exponential backoff — mirrors ApiService's
/// [ControlException] transient-vs-real split: a dropped socket is
/// reconnect-and-resume, not a hard error surfaced to the UI.
class MessagingApiService {
  final String baseUrl; // e.g. https://host:8452 — ws(s) derived from it

  static const _minBackoff = Duration(seconds: 1);
  static const _maxBackoff = Duration(seconds: 30);

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  Duration _backoff = _minBackoff;
  bool _disposed = false;

  final _messagesController = StreamController<Message>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  MessagingApiService(this.baseUrl);

  /// Fires for every message received from the paired device.
  Stream<Message> get messages => _messagesController.stream;

  /// true/false as the socket connects/drops — drive a "reconnecting…"
  /// indicator off this instead of treating a drop as a hard error.
  Stream<bool> get connectionState => _connectionController.stream;

  /// One-shot HTTP catch-up — used on first screen load and again after
  /// a reconnect, since the socket only delivers what arrives while
  /// it's actually open. [since] is epoch seconds; pass the last known
  /// message's sentAt to fetch only what was missed.
  Future<List<Message>> fetchHistory({double since = 0}) async {
    final res = await trustedHttp
        .get(Uri.parse('$baseUrl/api/messages?since=$since'))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw AppIssue.fromHttp(res.statusCode, res.body, doing: 'load messages');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['messages'] as List)
        .map((m) => Message.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<Uri> _wsUri() async {
    final uri = Uri.parse(baseUrl);
    final extra = await deviceTrust.signQuery('GET', '/ws');
    return uri.replace(
      scheme: uri.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws',
      queryParameters: extra.isEmpty ? null : extra,
    );
  }

  void connect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _openSocket();
  }

  Future<void> _openSocket() async {
    if (_disposed) return;
    final uri = await _wsUri();
    if (_disposed) return;
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;

    // WebSocketChannel.connect() returns immediately and connects lazily
    // in the background — it does NOT mean the handshake succeeded. Wait
    // on `.ready` (throws if the connection actually fails, e.g. nothing
    // listening on the other end) before telling the UI we're connected.
    // Without this, `connectionState` reports true the instant connect()
    // is called even when the desktop server is completely unreachable.
    channel.ready.then((_) {
      if (_disposed || _channel != channel) return; // superseded by a later connect()
      _connectionController.add(true);
      _backoff = _minBackoff;

      _sub = channel.stream.listen(
        (raw) {
          try {
            final data = jsonDecode(raw as String) as Map<String, dynamic>;
            _messagesController.add(Message.fromJson(data));
          } catch (_) {
            // Malformed frame — drop it, keep the socket alive.
          }
        },
        onError: (_) => _handleDrop(),
        onDone: _handleDrop,
        cancelOnError: true,
      );
    }).catchError((_) {
      if (_disposed || _channel != channel) return;
      _channel = null;
      _scheduleReconnect();
    });
  }

  void _handleDrop() {
    _connectionController.add(false);
    _sub?.cancel();
    _channel = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer = Timer(_backoff, connect);
    _backoff = Duration(
      seconds: (_backoff.inSeconds * 2).clamp(_minBackoff.inSeconds, _maxBackoff.inSeconds),
    );
  }

  /// Throws if not currently connected — caller queues and retries once
  /// [connectionState] emits true, rather than this swallowing the send.
  void send(Message message) {
    final channel = _channel;
    if (channel == null) throw StateError('not connected');
    channel.sink.add(jsonEncode(message.toJson()));
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close(ws_status.goingAway);
    _messagesController.close();
    _connectionController.close();
  }
}
