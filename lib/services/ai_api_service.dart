import 'dart:convert';
import '../models/ai_message.dart';
import 'trusted_http.dart';
import 'user_facing_error.dart';

/// Talks to modules/AI/web_server.py on :8454.
class AiApiService {
  final String baseUrl;
  final String? accessCode;
  AiApiService(this.baseUrl, {this.accessCode});

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (accessCode != null && accessCode!.isNotEmpty)
          'X-Access-Code': accessCode!,
      };

  Future<AiChatStatus> status() async {
    final res = await trustedHttp
        .get(_uri('/api/status'))
        .timeout(const Duration(seconds: 8));
    ensureOk(res, doing: 'reach AI Chat');
    return AiChatStatus.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<AiChatStatus> connect({
    required String source,
    String? apiKey,
    String? baseUrl,
    String? model,
  }) async {
    final res = await trustedHttp
        .post(
          _uri('/api/connect'),
          headers: _headers,
          body: jsonEncode({
            'source': source,
            if (apiKey != null && apiKey.isNotEmpty) 'api_key': apiKey,
            if (baseUrl != null && baseUrl.isNotEmpty) 'base_url': baseUrl,
            if (model != null && model.isNotEmpty) 'model': model,
          }),
        )
        .timeout(const Duration(seconds: 30));
    ensureOk(res, doing: 'connect AI Chat', requireOk: true);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['ready'] != true) {
      throw AppIssue.fromHttp(res.statusCode, res.body, doing: 'connect AI Chat');
    }
    return AiChatStatus.fromJson(data);
  }

  Future<List<AiMessage>> history() async {
    final res = await trustedHttp
        .get(_uri('/api/history'))
        .timeout(const Duration(seconds: 10));
    ensureOk(res, doing: 'load chat history');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['messages'] as List? ?? [])
        .map((m) => AiMessage.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<AiChatReply> send(String text, {bool agent = true}) async {
    final res = await trustedHttp
        .post(
          _uri('/api/chat'),
          headers: _headers,
          body: jsonEncode({'text': text, 'agent': agent}),
        )
        .timeout(const Duration(minutes: 10));
    ensureOk(res, doing: 'send that chat', requireOk: true);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return _replyFrom(data);
  }

  Future<AiChatReply> build(String prompt) async {
    final res = await trustedHttp
        .post(
          _uri('/api/build'),
          headers: _headers,
          body: jsonEncode({'prompt': prompt}),
        )
        .timeout(const Duration(minutes: 10));
    ensureOk(res, doing: 'run that build', requireOk: true);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return _replyFrom(data);
  }

  AiChatReply _replyFrom(Map<String, dynamic> data) {
    final tools = (data['tools'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final log = (data['log'] as List? ?? []).map((e) => e.toString()).join('\n');
    var reply = data['reply'] as String? ?? '';
    if (reply.isEmpty && data['path'] != null) {
      reply = 'Built on the PC:\n${data['path']}\n$log';
    }
    return AiChatReply(
      reply: reply,
      tools: tools,
      cleared: data['cleared'] == true,
      path: data['path'] as String? ?? '',
    );
  }

  Future<Map<String, dynamic>?> pendingConfirm() async {
    final res = await trustedHttp
        .get(_uri('/api/pending_confirm'), headers: _headers)
        .timeout(const Duration(seconds: 4));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final pending = data['pending'];
    if (pending is Map) return Map<String, dynamic>.from(pending);
    return null;
  }

  Future<void> answerConfirm(String id, bool ok) async {
    await trustedHttp
        .post(
          _uri('/api/confirm'),
          headers: _headers,
          body: jsonEncode({'id': id, 'ok': ok}),
        )
        .timeout(const Duration(seconds: 6));
  }

  Future<void> clear() async {
    final res = await trustedHttp
        .post(_uri('/api/clear'), headers: _headers, body: '{}')
        .timeout(const Duration(seconds: 8));
    ensureOk(res, doing: 'clear this chat', requireOk: true);
  }
}
