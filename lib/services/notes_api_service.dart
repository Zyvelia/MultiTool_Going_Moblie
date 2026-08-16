import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/note.dart';

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
    final res = await http
        .get(_uri('/api/notes', query.isEmpty ? null : {'q': query}));
    if (res.statusCode != 200) {
      throw Exception('Failed to load notes (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['notes'] as List)
        .map((n) => Note.fromJson(n as Map<String, dynamic>))
        .toList();
  }

  Future<Note> createNote({required String title, required String body}) async {
    final res = await http.post(_uri('/api/notes'),
        headers: _headers, body: jsonEncode({'title': title, 'body': body}));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || data['ok'] != true) {
      throw Exception('Failed to create note (${res.statusCode})');
    }
    return Note.fromJson(data['note'] as Map<String, dynamic>);
  }

  Future<Note> updateNote(String id,
      {required String title, required String body}) async {
    final res = await http.post(_uri('/api/notes/$id/update'),
        headers: _headers, body: jsonEncode({'title': title, 'body': body}));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || data['ok'] != true) {
      throw Exception('Failed to save note (${res.statusCode})');
    }
    return Note.fromJson(data['note'] as Map<String, dynamic>);
  }

  Future<void> deleteNote(String id) async {
    final res = await http.post(_uri('/api/notes/$id/delete'));
    if (res.statusCode != 200) {
      throw Exception('Failed to delete note (${res.statusCode})');
    }
  }

  Future<Note> togglePin(String id) async {
    final res = await http.post(_uri('/api/notes/$id/pin'));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 || data['ok'] != true) {
      throw Exception('Failed to toggle pin (${res.statusCode})');
    }
    return Note.fromJson(data['note'] as Map<String, dynamic>);
  }
}
