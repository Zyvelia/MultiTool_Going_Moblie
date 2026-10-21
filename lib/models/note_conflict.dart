import '../models/note.dart';
import '../services/notes_sync_service.dart';

class NoteConflict {
  NoteConflict({
    required this.noteId,
    required this.local,
    required this.server,
  });

  final String noteId;
  final LocalNote local;
  final Note server;
}
