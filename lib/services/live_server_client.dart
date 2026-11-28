import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Protocol 1, independent of the old Python module ports.
/// Only literal Tailscale IPv4 destinations are accepted; no DNS, redirects,
/// system HTTP proxies, public endpoints, or untrusted TLS overrides.
class LiveServerClient {
  final Uri base;
  final String _code;

  LiveServerClient(String url, String code)
      : base = parseAddress(url), _code = code.trim() {
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(_code)) {
      throw const FormatException('Paste the 64-character session access code from ZMT.');
    }
  }

  static Uri parseAddress(String input) {
    final value = input.trim();
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'http' || !uri.hasAuthority ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') || !uri.hasPort ||
        uri.port < 1024 || uri.port > 65535) {
      throw const FormatException('Use the exact HTTP Tailscale URL and port shown by ZMT.');
    }
    final ip = InternetAddress.tryParse(uri.host);
    final bytes = ip?.rawAddress;
    if (bytes == null || bytes.length != 4 || bytes[0] != 100 ||
        bytes[1] < 64 || bytes[1] > 127 || ip!.address != uri.host) {
      throw const FormatException('Only literal Tailscale IPv4 addresses (100.64.0.0/10) are supported.');
    }
    return Uri(scheme: 'http', host: uri.host, port: uri.port);
  }

  Future<Map<String, dynamic>> _get(String path, {bool authenticated = true, bool pairing = false, bool post = false, Map<String, String>? query, List<int>? payload, String? contentType}) async {
    final client = HttpClient()
      ..findProxy = (_) => 'DIRECT'
      ..connectionTimeout = const Duration(seconds: 5)
      ..autoUncompress = false;
    try {
      final request = await client.openUrl(pairing || post ? 'POST' : 'GET', base.replace(path: path, queryParameters: query))
          .timeout(const Duration(seconds: 6));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (post) {
        request.contentLength = payload?.length ?? 0;
        if (contentType != null) request.headers.set(HttpHeaders.contentTypeHeader, contentType);
      }
      if (pairing) {
        request.contentLength = 0;
        request.headers.set('X-Pairing-Code', _code);
      } else if (authenticated) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_code');
      }
      if (payload != null) request.add(payload);
      final response = await request.close().timeout(payload == null ? const Duration(seconds: 6) : const Duration(minutes: 2));
      if (response.statusCode == 401) {
        throw const LiveServerException('Access code expired, revoked or incorrect. Pair again from ZMT.');
      }
      if (response.statusCode != 200) {
        throw LiveServerException('Live Server returned HTTP ${response.statusCode}.');
      }
      final bytes = <int>[];
      await response.forEach((chunk) {
        if (bytes.length + chunk.length > 1024 * 1024) {
          throw const LiveServerException('Server response exceeded the size limit.');
        }
        bytes.addAll(chunk);
      }).timeout(const Duration(seconds: 8));
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map<String, dynamic>) {
        throw const LiveServerException('Unexpected Live Server response.');
      }
      return json;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> pair() async {
    final status = await _get('/api/v1/status', authenticated: false);
    if (status['protocol'] != 1 || status['auth_required'] != true) {
      throw const LiveServerException('This is not a compatible ZMT Live Server.');
    }
    final data = await _get('/api/v1/pair', authenticated: false, pairing: true);
    if (data['token'] is! String || data['device_id'] is! String) {
      throw const LiveServerException('Invalid pairing response.');
    }
    // Validate before passing the credential to the secure store.
    LiveServerClient(base.toString(), data['token'] as String);
    return data;
  }

  Future<Map<String, dynamic>> connect() async {
    final status = await _get('/api/v1/status', authenticated: false);
    if (status['protocol'] != 1 || status['status'] != 'ok' || status['auth_required'] != true) {
      throw const LiveServerException('This is not a compatible ZMT Live Server.');
    }
    final capabilities = await _get('/api/v1/capabilities');
    if (capabilities['protocol'] != 1) {
      throw const LiveServerException('Unsupported protocol version.');
    }
    return state();
  }

  Future<Map<String, dynamic>> capabilities() => _get('/api/v1/capabilities');

  Future<Map<String, dynamic>> musicLibrary({String query = '', int offset = 0}) =>
      _get('/api/v1/music/library', query: {'q': query, 'offset': '$offset', 'limit': '50'});

  static bool validTrackId(String id) => RegExp(r'^[0-9a-f]{64}
    final data = await _get('/api/v1/state');
    if (data['version'] is! String || data['modules'] is! List ||
        (data['media'] != null && data['media'] is! Map)) {
      throw const LiveServerException('Invalid Live Server state.');
    }
    return data;
  }
}

class LiveServerException implements Exception {
  const LiveServerException(this.message);
  final String message;
  @override
  String toString() => message;
}
).hasMatch(id);
  Uri musicUri(String id) {
    if (!validTrackId(id)) throw const FormatException('Invalid track ID.');
    return base.replace(path: '/api/v1/music/stream', queryParameters: {'id': id});
  }
  Map<String, String> get musicHeaders => {'Authorization': 'Bearer $_code'};

  Future<void> musicControl(String action, {String? id, double? value}) async {
    if (!const {'play','pause','next','previous','seek','play_track'}.contains(action)) {
      throw const FormatException('Unknown music action.');
    }
    if (id != null && !validTrackId(id)) throw const FormatException('Invalid track ID.');
    await _get('/api/v1/music/control', post: true, query: {
      'action': action,
      if (id != null) 'id': id,
      if (value != null) 'value': '$value',
    });
  }

  static const maxTransfer = 20 * 1024 * 1024;
  Future<Map<String,dynamic>> notes({int offset = 0}) =>
      _get('/api/v1/notes/list', query: {'offset': '$offset'});
  Future<Map<String,dynamic>> note(String id) =>
      _get('/api/v1/notes/get', query: {'id': id});
  Future<Map<String,dynamic>> saveNote(String title, String body, {String? id, String? revision}) =>
      _get('/api/v1/notes/save', post: true, contentType: 'application/json',
        payload: utf8.encode(jsonEncode({'id':id,'title':title,'body':body,'revision':revision})));
  Future<Map<String,dynamic>> files() => _get('/api/v1/files/list');
  Future<void> upload(String name, List<int> bytes) async {
    if (bytes.length > maxTransfer) throw const FormatException('Maximum file size is 20 MiB.');
    await _get('/api/v1/files/upload', post: true, query: {'name':name},
      payload: bytes, contentType: 'application/octet-stream');
  }
  Future<List<int>> download(String id) async {
    if (!validTrackId(id)) throw const FormatException('Invalid file ID.');
    final client = HttpClient()..findProxy = (_) => 'DIRECT'
      ..connectionTimeout = const Duration(seconds: 5)..autoUncompress = false;
    try {
      final req = await client.getUrl(base.replace(path:'/api/v1/files/download', queryParameters:{'id':id}))
          .timeout(const Duration(seconds: 10));
      req.followRedirects = false;
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_code');
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200 || res.contentLength < 0 || res.contentLength > maxTransfer) {
        throw const LiveServerException('File unavailable or download permission denied.');
      }
      final bytes = <int>[];
      await res.forEach((chunk) {
        if (bytes.length + chunk.length > maxTransfer) throw const LiveServerException('File too large.');
        bytes.addAll(chunk);
      }).timeout(const Duration(minutes: 2));
      if (bytes.length != res.contentLength) throw const LiveServerException('Incomplete transfer.');
      return bytes;
    } finally { client.close(force:true); }
  }

  Future<Map<String,dynamic>> aiModels() => _get('/api/v1/ai/models');
  Future<String> aiStart(String model, List<Map<String,String>> messages) async {
    final result = await _get('/api/v1/ai/start', post: true,
      contentType: 'application/json',
      payload: utf8.encode(jsonEncode({'model':model,'messages':messages})));
    final id = result['id'];
    if (id is! String || !RegExp(r'^[0-9a-f]{32} => _get('/api/v1/hardware');

  Future<Map<String, dynamic>> state() async {
    final data = await _get('/api/v1/state');
    if (data['version'] is! String || data['modules'] is! List ||
        (data['media'] != null && data['media'] is! Map)) {
      throw const LiveServerException('Invalid Live Server state.');
    }
    return data;
  }
}

class LiveServerException implements Exception {
  const LiveServerException(this.message);
  final String message;
  @override
  String toString() => message;
}
).hasMatch(id)) {
      throw const LiveServerException('Invalid generation ID.');
    }
    return id;
  }
  Future<Map<String,dynamic>> aiResult(String id) =>
    _get('/api/v1/ai/result', query:{'id':id});
  Future<void> aiCancel(String id) async {
    await _get('/api/v1/ai/cancel', post:true,query:{'id':id});
  }

  Future<Map<String, dynamic>> hardware() => _get('/api/v1/hardware');

  Future<Map<String, dynamic>> state() async {
    final data = await _get('/api/v1/state');
    if (data['version'] is! String || data['modules'] is! List ||
        (data['media'] != null && data['media'] is! Map)) {
      throw const LiveServerException('Invalid Live Server state.');
    }
    return data;
  }
}

class LiveServerException implements Exception {
  const LiveServerException(this.message);
  final String message;
  @override
  String toString() => message;
}
