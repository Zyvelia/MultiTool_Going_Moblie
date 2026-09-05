import 'dart:convert';
import '../models/note.dart';
import 'trusted_http.dart';
import 'user_facing_error.dart';

/// Talks to modules/notes/web_server.py. No access-code support — that
/// server doesn't gate anything (see its own header comment), matching
/// Music Player's trust model rather than Gaming Hub's.
class NotesApiService {
  final String baseUrl;
  NotesApiService(this.baseUrl);

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  static const _headers = {'Content-Type': 'application/json'};

  Future<List<Note>> fetchNotes({String query = ''}) async {
    final res = await trustedHttp
        .get(_uri('/api/notes', query.isEmpty ? null : {'q': query}));
    ensureOk(res, doing: 'load notes');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['notes'] as List)
        .map((n) => Note.fromJson(n as Map<String, dynamic>))
        .toList();
  }

  Future<Note> createNote({required String title, required String body}) async {
    final res = await trustedHttp.post(_uri('/api/notes'),
        headers: _headers, body: jsonEncode({'title': title, 'body': body}));
    ensureOk(res, doing: 'create that note', requireOk: true);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return Note.fromJson(data['note'] as Map<String, dynamic>);
  }

  Future<Note> updateNote(String id,
      {required String title, required String body}) async {
    final res = await trustedHttp.post(_uri('/api/notes/$id/update'),
        headers: _headers, body: jsonEncode({'title': title, 'body': body}));
    ensureOk(res, doing: 'save that note', requireOk: true);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return Note.fromJson(data['note'] as Map<String, dynamic>);
  }

  Future<void> deleteNote(String id) async {
    final res = await trustedHttp.post(_uri('/api/notes/$id/delete'));
    ensureOk(res, doing: 'delete that note');
  }

  Future<Note> togglePin(String id) async {
    final res = await trustedHttp.post(_uri('/api/notes/$id/pin'));
    ensureOk(res, doing: 'pin that note', requireOk: true);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return Note.fromJson(data['note'] as Map<String, dynamic>);
  }
}
