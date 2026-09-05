import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'settings_service.dart';
import 'user_facing_error.dart';

/// Pair this phone to the PC. The secret never leaves Keychain /
/// EncryptedSharedPreferences. Revoke on Remote Hub is the kill switch.
class DeviceTrustService {
  final SettingsService _settings = SettingsService();

  Future<String?> getSecret() => _settings.getDeviceSecret();

  Future<bool> isPaired() async {
    final secret = await getSecret();
    return secret != null && secret.isNotEmpty;
  }

  Future<void> clearSecret() => _settings.clearDeviceSecret();

  Future<Map<String, String>> signHeaders(String method, String path) async {
    final secret = await getSecret();
    if (secret == null || secret.isEmpty) return {};
    final id = await _settings.getOrCreateDeviceId();
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final msg = '$ts.${method.toUpperCase()}.$path';
    final sig = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(msg)).toString();
    return {
      'X-Device-Id': id,
      'X-Device-Ts': ts,
      'X-Device-Sig': sig,
    };
  }

  Future<Map<String, String>> signQuery(String method, String path) async {
    final headers = await signHeaders(method, path);
    if (headers.isEmpty) return {};
    return {
      'device_id': headers['X-Device-Id']!,
      'ts': headers['X-Device-Ts']!,
      'sig': headers['X-Device-Sig']!,
    };
  }

  Uri _trustUri(String host, String path) =>
      Uri.parse('https://$host:${ModulePorts.trust}$path');

  Future<TrustStatus> status(String host) async {
    final res = await http
        .get(_trustUri(host, '/api/status'))
        .timeout(const Duration(seconds: 8));
    ensureOk(res, doing: 'reach the pairing server', requireOk: true);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return TrustStatus(
      required: data['required'] == true,
      devices: (data['devices'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
    );
  }

  Future<void> pair(String host, String code, {String label = 'phone'}) async {
    final id = await _settings.getOrCreateDeviceId();
    final res = await http
        .post(
          _trustUri(host, '/api/pair'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'code': code.trim(),
            'device_id': id,
            'label': label.trim().isEmpty ? 'phone' : label.trim(),
          }),
        )
        .timeout(const Duration(seconds: 12));
    ensureOk(res, doing: 'pair this phone', requireOk: true);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final secret = data['secret'] as String? ?? '';
    if (secret.isEmpty) {
      throw const AppIssue('The PC did not finish pairing. Issue a new code on Remote Hub and try again.');
    }
    await _settings.setDeviceSecret(secret);
  }
}

class TrustStatus {
  final bool required;
  final List<Map<String, dynamic>> devices;
  TrustStatus({required this.required, required this.devices});
}

final deviceTrust = DeviceTrustService();
