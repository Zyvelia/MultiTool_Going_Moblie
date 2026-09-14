import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/ai_approval.dart';
import 'trusted_http.dart';
import 'user_facing_error.dart';

/// Remote approval API used by the PC AI. The mobile app never receives
/// filesystem access; it only authorizes a specific pending operation.
class AiApprovalService {
  final String baseUrl;
  final String? accessCode;

  AiApprovalService(this.baseUrl, {this.accessCode});

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (accessCode != null && accessCode!.isNotEmpty) 'X-Access-Code': accessCode!,
      };

  Future<AiApproval?> pending() async {
    final res = await trustedHttp
        .get(_uri('/api/ai/approvals/pending'), headers: _headers)
        .timeout(const Duration(seconds: 6));
    if (res.statusCode == 404) return _pendingLegacy();
    ensureOk(res, doing: 'load AI approvals');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = data['approval'] ?? data['pending'];
    if (raw is! Map) return null;
    return AiApproval.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<AiApproval?> get(String id) async {
    final encoded = Uri.encodeComponent(id);
    final res = await trustedHttp
        .get(_uri('/api/ai/approvals/$encoded'), headers: _headers)
        .timeout(const Duration(seconds: 6));
    if (res.statusCode == 404) return pending();
    ensureOk(res, doing: 'load AI approval');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = data['approval'] ?? data['pending'];
    if (raw is! Map) return null;
    return AiApproval.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<void> decide(String id, bool accepted) async {
    final encoded = Uri.encodeComponent(id);
    final res = await trustedHttp
        .post(
          _uri('/api/ai/approvals/$encoded/decision'),
          headers: _headers,
          body: jsonEncode({'approved': accepted, 'ok': accepted}),
        )
        .timeout(const Duration(seconds: 8));
    if (res.statusCode == 404) {
      // Compatibility with the existing desktop confirmation API.
      final legacy = await trustedHttp
          .post(
            _uri('/api/confirm'),
            headers: _headers,
            body: jsonEncode({'id': id, 'ok': accepted}),
          )
          .timeout(const Duration(seconds: 8));
      ensureOk(legacy, doing: accepted ? 'approve the AI operation' : 'deny the AI operation');
      return;
    }
    ensureOk(res, doing: accepted ? 'approve the AI operation' : 'deny the AI operation');
  }

  Future<void> registerFcmToken(String token, {required String platform}) async {
    final res = await trustedHttp
        .post(
          _uri('/api/ai/mobile/fcm-token'),
          headers: _headers,
          body: jsonEncode({'token': token, 'platform': platform, 'purpose': 'ai_approval'}),
        )
        .timeout(const Duration(seconds: 8));
    // Older PC AI builds do not have this endpoint. Mobile still registers
    // the token with the existing Inbox Worker in that case.
    if (res.statusCode == 404) return;
    ensureOk(res, doing: 'register AI approval notifications');
  }

  Future<AiApproval?> _pendingLegacy() async {
    final res = await trustedHttp
        .get(_uri('/api/pending_confirm'), headers: _headers)
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = data['pending'];
    if (raw is! Map) return null;
    return AiApproval.fromJson(Map<String, dynamic>.from(raw));
  }
}
