import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/mirrored_notification.dart';

/// Wraps modules/notification_mirror/web_server.py. Same request/response
/// pattern as every other *ApiService in this app, plus one addition:
/// [stream], a hand-rolled Server-Sent Events client built on the `http`
/// package's streamed [http.Client.send] rather than a new WebSocket
/// dependency — the PC -> phone direction is all this feature needs
/// (see the web server's own header comment for why).
class NotificationsApiService {
  final String baseUrl;
  http.Client? _streamClient;
  Timer? _reconnectTimer;
  bool _wantStream = false;
  int _lastSeq = 0;

  NotificationsApiService(this.baseUrl);

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, dynamic>> getStatus() async {
    final res = await http.get(_uri('/api/status')).timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) throw Exception('Status check failed (${res.statusCode})');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getSettings() async {
    final res = await http.get(_uri('/api/settings')).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw Exception('Failed to load settings (${res.statusCode})');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> updateSettings(Map<String, dynamic> partial) async {
    final res = await http
        .post(_uri('/api/settings'),
            headers: {'Content-Type': 'application/json'}, body: jsonEncode(partial))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw Exception('Failed to save settings (${res.statusCode})');
  }

  Future<void> setEnabled(bool enabled) async {
    final res = await http
        .post(_uri('/api/enable'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'enabled': enabled}))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw Exception('Failed to toggle mirroring (${res.statusCode})');
  }

  Future<void> setAppEnabled(String appName, bool enabled) async {
    await updateSettings({
      'apps': {appName: enabled}
    });
  }

  Future<List<MirroredNotification>> getHistory() async {
    final res = await http.get(_uri('/api/history')).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw Exception('Failed to load history (${res.statusCode})');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['items'] as List)
        .map((e) => MirroredNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> clearHistory() async {
    final res = await http.delete(_uri('/api/history')).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw Exception('Failed to clear history (${res.statusCode})');
  }

  /// Best-effort only — see the PC-side /api/dismiss handler's own
  /// comment. This clears the entry from Windows' Action Center, not
  /// from whatever app originally posted it.
  Future<void> dismiss(int notificationId) async {
    await http
        .post(_uri('/api/dismiss'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'id': notificationId}))
        .timeout(const Duration(seconds: 8));
  }

  // =====================================================
  // REAL-TIME STREAM (SSE over the `http` package's streamed response —
  // no websocket dependency needed for a one-directional server->client
  // feed). Reconnects with backoff, and resumes from the last seen
  // event id via ?since=, which lets the PC-side backlog (see
  // web_server.py's _Broker) fill in anything missed during a short drop.
  // =====================================================

  final _controller = StreamController<MirroredNotification>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  Stream<MirroredNotification> get onNotification => _controller.stream;

  /// True while the SSE connection is actually open — drives the
  /// "Phone offline / Connected" indicator in the UI.
  Stream<bool> get onConnectionChange => _connectionController.stream;

  void startStream() {
    if (_wantStream) return;
    _wantStream = true;
    _connect();
  }

  void stopStream() {
    _wantStream = false;
    _reconnectTimer?.cancel();
    _streamClient?.close();
    _streamClient = null;
  }

  Future<void> _connect() async {
    if (!_wantStream) return;
    _streamClient?.close();
    final client = http.Client();
    _streamClient = client;

    try {
      final request = http.Request('GET', _uri('/api/stream?since=$_lastSeq'));
      final response = await client.send(request).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('Stream connect failed (${response.statusCode})');
      }
      _connectionController.add(true);

      var buffer = '';
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        buffer += chunk;
        // SSE frames are separated by a blank line; each frame may have
        // an "id:" line and a "data:" line.
        while (buffer.contains('\n\n')) {
          final idx = buffer.indexOf('\n\n');
          final frame = buffer.substring(0, idx);
          buffer = buffer.substring(idx + 2);
          _handleFrame(frame);
        }
      }
      // Stream ended cleanly (server closed it) — treat like a drop.
      throw Exception('Stream closed by server');
    } catch (_) {
      _connectionController.add(false);
      _scheduleReconnect();
    }
  }

  void _handleFrame(String frame) {
    String? data;
    for (final line in frame.split('\n')) {
      if (line.startsWith('data: ')) data = line.substring(6);
    }
    if (data == null) return; // heartbeat comment lines have no "data:"
    try {
      final event = jsonDecode(data) as Map<String, dynamic>;
      final seq = (event['seq'] as num?)?.toInt();
      if (seq != null) _lastSeq = seq;

      if (event['type'] == 'notification') {
        _controller.add(MirroredNotification.fromJson(event));
      }
      // event['type'] == 'dismissed' / 'status' — surfaced to any screen
      // that wants finer-grained handling later; MVP just needs the
      // "notification" case to post a native mobile notification.
    } catch (_) {
      // malformed frame — drop it rather than crash the stream
    }
  }

  void _scheduleReconnect() {
    if (!_wantStream) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), _connect);
  }

  void dispose() {
    stopStream();
    _controller.close();
    _connectionController.close();
  }
}
