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

  Future<Map<String, dynamic>> _get(String path, {bool authenticated = true}) async {
    final client = HttpClient()
      ..findProxy = (_) => 'DIRECT'
      ..connectionTimeout = const Duration(seconds: 5)
      ..autoUncompress = false;
    try {
      final request = await client.getUrl(base.replace(path: path))
          .timeout(const Duration(seconds: 6));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (authenticated) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_code');
      }
      final response = await request.close().timeout(const Duration(seconds: 6));
      if (response.statusCode == 401) {
        throw const LiveServerException('Access code expired or incorrect. Copy the current code from ZMT.');
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
