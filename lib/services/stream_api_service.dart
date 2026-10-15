import 'dart:convert';
import 'trusted_http.dart';
import 'user_facing_error.dart';

class StreamCapabilities {
  final bool lock;
  final bool sleep;
  final bool shutdown;
  final bool restart;
  final bool remoteScreen;
  final bool remoteInput;
  final int remoteFps;
  final bool remoteWebrtc;

  const StreamCapabilities({
    required this.lock,
    required this.sleep,
    required this.shutdown,
    required this.restart,
    this.remoteScreen = true,
    this.remoteInput = true,
    this.remoteFps = 8,
    this.remoteWebrtc = false,
  });

  factory StreamCapabilities.fromJson(Map<String, dynamic> json) {
    final actions = json['actions'] as Map<String, dynamic>? ?? {};
    final rd = json['remote_desktop'] as Map<String, dynamic>? ?? {};
    return StreamCapabilities(
      lock: actions['lock'] == true,
      sleep: actions['sleep'] == true,
      shutdown: actions['shutdown'] == true,
      restart: actions['restart'] == true,
      remoteScreen: rd['screen'] != false,
      remoteInput: rd['input'] != false,
      remoteFps: (rd['fps'] as num?)?.toInt() ?? 8,
      remoteWebrtc: rd['webrtc'] == true,
    );
  }
}

class WebRtcAnswer {
  final String sdp;
  final String type;

  const WebRtcAnswer({required this.sdp, required this.type});
}

class StreamStatus {
  final String hostname;
  final int uptimeSeconds;
  final bool wolConfigured;

  const StreamStatus({
    required this.hostname,
    required this.uptimeSeconds,
    required this.wolConfigured,
  });

  factory StreamStatus.fromJson(Map<String, dynamic> json) {
    return StreamStatus(
      hostname: (json['hostname'] as String?) ?? 'PC',
      uptimeSeconds: (json['uptime_seconds'] as num?)?.toInt() ?? 0,
      wolConfigured: json['wol_configured'] == true,
    );
  }
}

class StreamHealth {
  final bool reachable;
  final String hostname;
  final bool screenStream;
  final bool remoteInput;
  final bool webrtcEnabled;
  final bool webrtcAvailable;
  final bool webrtcActive;
  final String? webrtcError;

  const StreamHealth({
    required this.reachable,
    required this.hostname,
    required this.screenStream,
    required this.remoteInput,
    required this.webrtcEnabled,
    required this.webrtcAvailable,
    required this.webrtcActive,
    this.webrtcError,
  });

  factory StreamHealth.fromJson(Map<String, dynamic> json) {
    final w = json['webrtc'] as Map<String, dynamic>? ?? {};
    return StreamHealth(
      reachable: json['reachable'] == true || json['ok'] == true,
      hostname: (json['hostname'] as String?) ?? 'PC',
      screenStream: json['screen_stream'] != false,
      remoteInput: json['remote_input'] != false,
      webrtcEnabled: w['enabled'] != false,
      webrtcAvailable: w['available'] == true,
      webrtcActive: w['active'] == true,
      webrtcError: (w['error'] as String?)?.trim().isEmpty == true
          ? null
          : w['error'] as String?,
    );
  }
}

class WolConfig {
  final String macAddress;
  final String broadcast;
  final int port;

  const WolConfig({
    required this.macAddress,
    required this.broadcast,
    required this.port,
  });

  factory WolConfig.fromJson(Map<String, dynamic> json) {
    return WolConfig(
      macAddress: (json['mac_address'] as String?) ?? '',
      broadcast: (json['broadcast'] as String?) ?? '255.255.255.255',
      port: (json['port'] as num?)?.toInt() ?? 9,
    );
  }
}

/// Talks to modules/Network/stream_service/web_server.py on the desktop app.
class StreamApiService {
  final String baseUrl;
  final String? accessCode;

  StreamApiService(this.baseUrl, {this.accessCode});

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (accessCode != null && accessCode!.isNotEmpty)
          'X-Access-Code': accessCode!,
      };

  Future<StreamHealth?> fetchHealth() async {
    try {
      final res = await trustedHttp
          .get(_uri('/api/health'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      return StreamHealth.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Poll until Stream Service answers on Tailscale (e.g. after WoL).
  Future<bool> waitUntilOnline({
    Duration timeout = const Duration(minutes: 4),
    Duration interval = const Duration(seconds: 4),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (await checkStatus()) return true;
      await Future<void>.delayed(interval);
    }
    return false;
  }

  Future<bool> checkStatus() async {
    try {
      final res = await trustedHttp
          .get(_uri('/api/status'))
          .timeout(const Duration(seconds: 6));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<StreamStatus> fetchStatus() async {
    final res = await trustedHttp.get(_uri('/api/status'));
    ensureOk(res, doing: 'reach Stream Service on the PC');
    return StreamStatus.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<WolConfig> fetchWolConfig() async {
    final res = await trustedHttp.get(_uri('/api/wol'));
    ensureOk(res, doing: 'load wake settings from the PC');
    return WolConfig.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<StreamCapabilities> fetchCapabilities() async {
    final res = await trustedHttp.get(_uri('/api/capabilities'));
    ensureOk(res, doing: 'load PC control permissions');
    return StreamCapabilities.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<WebRtcAnswer> webrtcOffer({required String sdp, required String type}) async {
    final res = await trustedHttp.post(
      _uri('/api/webrtc/offer'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'sdp': sdp, 'type': type}),
    );
    ensureOk(res, doing: 'start WebRTC screen share');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['ok'] != true) {
      throw AppIssue((data['error'] as String?) ?? 'WebRTC negotiation failed');
    }
    final answerSdp = data['sdp'] as String? ?? '';
    if (answerSdp.isEmpty) {
      throw AppIssue('PC returned an empty WebRTC answer');
    }
    return WebRtcAnswer(
      sdp: answerSdp,
      type: (data['type'] as String?) ?? 'answer',
    );
  }

  Future<void> stopWebrtc() async {
    try {
      await trustedHttp.post(
        _uri('/api/webrtc/stop'),
        headers: {'Content-Type': 'application/json'},
        body: '{}',
      );
    } catch (_) {
      // Best-effort when leaving the viewer.
    }
  }

  Future<List<int>> fetchScreenFrame() async {
    final res = await trustedHttp.get(_uri('/api/screen/frame'));
    ensureOk(res, doing: 'load the PC screen');
    return res.bodyBytes;
  }

  Future<void> sendInput({
    required String type,
    required double x,
    required double y,
    int? delta,
    String button = 'left',
  }) async {
    final res = await trustedHttp.post(
      _uri('/api/input'),
      headers: _headers,
      body: jsonEncode({
        'type': type,
        'x': x,
        'y': y,
        if (delta != null) 'delta': delta,
        'button': button,
      }),
    );
    ensureOk(res, doing: 'send remote input', requireOk: true);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['ok'] != true) {
      throw AppIssue((data['message'] as String?) ?? 'Input failed');
    }
  }

  Future<void> power(String action) async {
    final res = await trustedHttp.post(
      _uri('/api/power'),
      headers: _headers,
      body: jsonEncode({'action': action}),
    );
    ensureOk(res, doing: 'run that power action', requireOk: true);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['ok'] != true) {
      throw AppIssue(
        (data['message'] as String?) ?? (data['error'] as String?) ?? 'Power action failed',
      );
    }
  }
}
