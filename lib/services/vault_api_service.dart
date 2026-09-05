import 'dart:convert';
import '../models/vault_entry.dart';
import 'trusted_http.dart';
import 'user_facing_error.dart';

/// Talks to core/services/vault_web_server.py. Uses the Bearer-token
/// path (same session store as the cookie path — see
/// _bearer_from_headers in vault_web_server.py) since a plain http
/// client doesn't manage cookies across requests. The token only ever
/// lives in memory for this app run; nothing is written to disk.
class VaultApiService {
  final String baseUrl;
  VaultApiService(this.baseUrl);

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<bool> checkStatus() async {
    try {
      final res =
          await trustedHttp.get(_uri('/api/session')).timeout(const Duration(seconds: 6));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Returns the session token on success, throws on failure.
  Future<String> login(String password) async {
    final res = await trustedHttp
        .post(_uri('/api/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'password': password}))
        .timeout(const Duration(seconds: 10));
    ensureOk(res, doing: 'unlock the vault');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['token'] as String;
  }

  Future<void> logout(String token) async {
    try {
      await trustedHttp.post(_uri('/api/logout'),
          headers: {'Authorization': 'Bearer $token'});
    } catch (_) {
      // best-effort — session will also just expire server-side
    }
  }

  Future<List<VaultEntry>> fetchEntries(String token) async {
    final res = await trustedHttp.get(_uri('/api/entries'),
        headers: {'Authorization': 'Bearer $token'});
    if (res.statusCode != 200) {
      throw AppIssue.fromHttp(res.statusCode, res.body, doing: 'load vault entries');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['entries'] as List)
        .map((e) => VaultEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<TotpCode>> fetchTotpCodes(String token) async {
    final res = await trustedHttp.get(_uri('/api/totp'),
        headers: {'Authorization': 'Bearer $token'});
    if (res.statusCode != 200) {
      throw AppIssue.fromHttp(res.statusCode, res.body, doing: 'load authenticator codes');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['codes'] as List)
        .map((c) => TotpCode.fromJson(c as Map<String, dynamic>))
        .toList();
  }
}
