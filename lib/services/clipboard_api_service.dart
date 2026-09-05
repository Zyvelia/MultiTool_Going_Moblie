import 'dart:convert';
import '../models/clipboard_entry.dart';
import 'trusted_http.dart';
import 'user_facing_error.dart';

/// Talks to modules/clipboard_manager/web_server.py. No access-code
/// support — that server doesn't gate anything, matching Notes/Music
/// Player's trust model rather than Gaming Hub's. Read/browse only from
/// the phone's side; capture (PC clipboard -> history) happens entirely
/// on the desktop, independent of whether this ever gets called.
class ClipboardApiService {
  final String baseUrl;
  ClipboardApiService(this.baseUrl);

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<List<ClipboardEntry>> fetchEntries({String query = ''}) async {
    final res = await trustedHttp
        .get(_uri('/api/clipboard', query.isEmpty ? null : {'q': query}));
    if (res.statusCode != 200) {
      throw AppIssue.fromHttp(res.statusCode, res.body, doing: 'load clipboard history');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['entries'] as List)
        .map((e) => ClipboardEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> togglePin(String id) async {
    final res = await trustedHttp.post(_uri('/api/clipboard/$id/pin'));
    if (res.statusCode != 200) {
      throw AppIssue.fromHttp(res.statusCode, res.body, doing: 'pin that clip');
    }
  }

  Future<void> deleteEntry(String id) async {
    final res = await trustedHttp.delete(_uri('/api/clipboard/$id'));
    if (res.statusCode != 200) {
      throw AppIssue.fromHttp(res.statusCode, res.body, doing: 'delete that clip');
    }
  }

  Future<void> clearUnpinned() async {
    final res = await trustedHttp.post(_uri('/api/clipboard/clear-unpinned'));
    if (res.statusCode != 200) {
      throw AppIssue.fromHttp(res.statusCode, res.body, doing: 'clear unpinned clips');
    }
  }
}
