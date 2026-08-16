import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/note.dart';
import 'notes_api_service.dart';

enum NoteSyncState { synced, pendingCreate, pendingUpdate, pendingDelete }

/// A note plus sync bookkeeping. Notes created while offline get a
/// `local_<id>` placeholder id (see [NotesSyncService.createNote]); once
/// [NotesSyncService.sync] pushes that create to the desktop, the entry
/// is re-keyed under the real server id.
class LocalNote {
  final String id;
  String title;
  String body;
  bool pinned;
  double updatedAt;
  NoteSyncState syncState;

  LocalNote({
    required this.id,
    required this.title,
    required this.body,
    required this.pinned,
    required this.updatedAt,
    this.syncState = NoteSyncState.synced,
  });

  factory LocalNote.fromNote(Note n, {NoteSyncState syncState = NoteSyncState.synced}) =>
      LocalNote(
        id: n.id,
        title: n.title,
        body: n.body,
        pinned: n.pinned,
        updatedAt: n.updatedAt,
        syncState: syncState,
      );

  factory LocalNote.fromJson(Map<String, dynamic> j) => LocalNote(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        pinned: j['pinned'] as bool? ?? false,
        updatedAt: (j['updatedAt'] as num?)?.toDouble() ?? 0,
        syncState: NoteSyncState.values.firstWhere(
          (s) => s.name == (j['syncState'] as String? ?? 'synced'),
          orElse: () => NoteSyncState.synced,
        ),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'pinned': pinned,
        'updatedAt': updatedAt,
        'syncState': syncState.name,
      };

  // Notes only ever have real links from the desktop side; nothing here
  // creates or edits them, so the round trip through LocalNote drops
  // them rather than trying to preserve/re-serialize.
  Note toNote() => Note(
        id: id,
        title: title,
        body: body,
        links: const [],
        updatedAt: updatedAt,
        pinned: pinned,
      );

  bool get isLocalOnly => id.startsWith('local_');
}

enum NotesSyncEventType { syncStarted, syncFinished }

class NotesSyncEvent {
  final NotesSyncEventType type;
  final int? synced;
  final int? failed;
  const NotesSyncEvent(this.type, {this.synced, this.failed});
}

/// Local-first storage for the Notes tab: every read and write goes
/// through here instead of hitting [NotesApiService] directly, so notes
/// can be browsed, created, edited, and deleted with zero connection to
/// the desktop. Changes made offline are queued (one pending op per
/// note — a note edited three times offline just carries the latest
/// content, not three replayed edits) and pushed to
/// modules/notes/web_server.py the next time [sync] runs, which
/// NotesScreen calls on pull-to-refresh and on every offline->online
/// connectivity edge.
///
/// Conflict policy is deliberately simple: whatever's newest *locally*
/// wins on sync (a local pendingUpdate/pendingCreate always overwrites
/// the desktop's copy). If the same note was also edited directly on
/// the desktop while the phone was offline, that desktop edit is lost —
/// there's no merge here, just last-writer-wins from the phone's queue.
class NotesSyncService {
  NotesSyncService._internal();
  static final NotesSyncService instance = NotesSyncService._internal();

  final StreamController<NotesSyncEvent> _events =
      StreamController<NotesSyncEvent>.broadcast();
  Stream<NotesSyncEvent> get events => _events.stream;

  Directory? _dir;
  final Map<String, LocalNote> _notes = {}; // keyed by current (local or server) id
  bool _initialized = false;
  Future<void>? _initFuture;
  bool _syncing = false;
  bool get isSyncing => _syncing;

  Future<void> ensureReady() => _initFuture ??= _init();

  Future<void> _init() async {
    final docs = await getApplicationDocumentsDirectory();
    _dir = Directory('${docs.path}/notes_cache');
    await _dir!.create(recursive: true);
    await _load();
    _initialized = true;
  }

  bool get isReady => _initialized;

  File get _file => File('${_dir!.path}/notes.json');

  Future<void> _load() async {
    try {
      final f = _file;
      if (!await f.exists()) return;
      final raw = jsonDecode(await f.readAsString()) as List;
      for (final item in raw) {
        try {
          final n = LocalNote.fromJson(item as Map<String, dynamic>);
          _notes[n.id] = n;
        } catch (_) {
          // One corrupt entry shouldn't take down the whole cache.
        }
      }
    } catch (_) {
      // Corrupt/unreadable cache file — start empty rather than crash
      // the Notes tab on open.
    }
  }

  Future<void> _save() async {
    if (_dir == null) return;
    final list = _notes.values.map((n) => n.toJson()).toList();
    await _file.writeAsString(jsonEncode(list));
  }

  /// Pinned first, then most-recently-updated — mirrors the ordering
  /// the desktop server applies, since offline browsing has no server
  /// to ask. Notes queued for deletion are hidden immediately even
  /// though they're not actually gone from the server until [sync]
  /// catches up.
  List<Note> localNotes({String query = ''}) {
    var list = _notes.values
        .where((n) => n.syncState != NoteSyncState.pendingDelete)
        .toList();
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      list = list
          .where((n) =>
              n.title.toLowerCase().contains(q) ||
              n.body.toLowerCase().contains(q))
          .toList();
    }
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list.map((n) => n.toNote()).toList();
  }

  int get pendingCount =>
      _notes.values.where((n) => n.syncState != NoteSyncState.synced).length;

  bool isPending(String id) {
    final n = _notes[id];
    return n != null && n.syncState != NoteSyncState.synced;
  }

  /// Merges a fresh fetch from the desktop into the local cache. Notes
  /// with unsynced local changes are left untouched — overwriting a
  /// queued edit with a mid-flight server response would just lose it.
  Future<void> replaceFromServer(List<Note> serverNotes) async {
    await ensureReady();
    final pendingIds = _notes.entries
        .where((e) => e.value.syncState != NoteSyncState.synced)
        .map((e) => e.key)
        .toSet();
    _notes.removeWhere((id, _) => !pendingIds.contains(id));
    for (final n in serverNotes) {
      if (pendingIds.contains(n.id)) continue;
      _notes[n.id] = LocalNote.fromNote(n);
    }
    await _save();
  }

  /// After a successful direct API call (e.g. togglePin, which has no
  /// local-first queueing of its own), reconciles that one note into
  /// the cache without disturbing anything else's pending state.
  Future<void> upsertFromServer(Note n) async {
    await ensureReady();
    _notes[n.id] = LocalNote.fromNote(n);
    await _save();
  }

  Future<Note> createNote({required String title, required String body}) async {
    await ensureReady();
    final id = 'local_${DateTime.now().microsecondsSinceEpoch}';
    final note = LocalNote(
      id: id,
      title: title,
      body: body,
      pinned: false,
      updatedAt: DateTime.now().millisecondsSinceEpoch / 1000,
      syncState: NoteSyncState.pendingCreate,
    );
    _notes[id] = note;
    await _save();
    return note.toNote();
  }

  Future<Note> updateNote(String id, {required String title, required String body}) async {
    await ensureReady();
    final existing = _notes[id];
    if (existing == null) throw Exception('Note not found locally');
    existing.title = title;
    existing.body = body;
    existing.updatedAt = DateTime.now().millisecondsSinceEpoch / 1000;
    // A note still waiting on its initial create just carries the newer
    // content into that same pending create — no separate update op to
    // queue since the desktop doesn't know this note exists yet.
    if (existing.syncState == NoteSyncState.synced) {
      existing.syncState = NoteSyncState.pendingUpdate;
    }
    await _save();
    return existing.toNote();
  }

  Future<void> deleteNote(String id) async {
    await ensureReady();
    final existing = _notes[id];
    if (existing == null) return;
    if (existing.syncState == NoteSyncState.pendingCreate) {
      // Never made it to the server — nothing to sync, just drop it.
      _notes.remove(id);
    } else {
      existing.syncState = NoteSyncState.pendingDelete;
    }
    await _save();
  }

  /// Pushes every queued local change to the desktop, oldest edit
  /// first. Best-effort per note: one failure (server unreachable
  /// mid-batch, a note rejected for some reason) doesn't stop the rest
  /// from syncing, and whatever failed just stays queued for the next
  /// attempt.
  Future<void> sync(NotesApiService api) async {
    await ensureReady();
    if (_syncing) return;
    final pending = _notes.values
        .where((n) => n.syncState != NoteSyncState.synced)
        .toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    if (pending.isEmpty) return;

    _syncing = true;
    var synced = 0;
    var failed = 0;
    _events.add(const NotesSyncEvent(NotesSyncEventType.syncStarted));

    for (final n in pending) {
      try {
        switch (n.syncState) {
          case NoteSyncState.pendingCreate:
            final created = await api.createNote(title: n.title, body: n.body);
            _notes.remove(n.id);
            _notes[created.id] = LocalNote.fromNote(created);
            break;
          case NoteSyncState.pendingUpdate:
            final updated = await api.updateNote(n.id, title: n.title, body: n.body);
            _notes[n.id] = LocalNote.fromNote(updated);
            break;
          case NoteSyncState.pendingDelete:
            await api.deleteNote(n.id);
            _notes.remove(n.id);
            break;
          case NoteSyncState.synced:
            break;
        }
        synced++;
      } catch (_) {
        failed++;
        // Leave it queued as-is; the next sync (or the next
        // offline->online edge) retries it.
      }
    }

    await _save();
    _syncing = false;
    _events.add(NotesSyncEvent(
      NotesSyncEventType.syncFinished,
      synced: synced,
      failed: failed,
    ));
  }
}
