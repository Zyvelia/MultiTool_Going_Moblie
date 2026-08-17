import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/clipboard_entry.dart';

/// Simple read-through disk cache for the Clipboard tab: whatever was
/// last fetched from modules/clipboard_manager/web_server.py is saved
/// to disk, so reopening the tab (or opening it with no connection at
/// all) still shows the last-known history instead of a blank screen.
///
/// Unlike NotesSyncService, there's no offline write queue here — pin
/// and delete are simple direct API calls with no local-first editing
/// story, since clipboard entries are captured on the desktop, not
/// created on the phone. Being offline just means those actions are
/// unavailable until reconnected (ClipboardScreen handles that), same
/// as NotesScreen's own togglePin does.
class ClipboardCacheService {
  ClipboardCacheService._internal();
  static final ClipboardCacheService instance = ClipboardCacheService._internal();

  Directory? _dir;
  List<ClipboardEntry> _entries = [];
  bool _initialized = false;
  Future<void>? _initFuture;

  Future<void> ensureReady() => _initFuture ??= _init();

  Future<void> _init() async {
    final docs = await getApplicationDocumentsDirectory();
    _dir = Directory('${docs.path}/clipboard_cache');
    await _dir!.create(recursive: true);
    await _load();
    _initialized = true;
  }

  bool get isReady => _initialized;

  File get _file => File('${_dir!.path}/entries.json');

  Future<void> _load() async {
    try {
      final f = _file;
      if (!await f.exists()) return;
      final raw = jsonDecode(await f.readAsString()) as List;
      _entries = raw
          .map((e) {
            try {
              return ClipboardEntry.fromJson(e as Map<String, dynamic>);
            } catch (_) {
              return null; // one corrupt entry shouldn't drop the whole cache
            }
          })
          .whereType<ClipboardEntry>()
          .toList();
    } catch (_) {
      // Corrupt/unreadable cache file — start empty rather than crash
      // the Clipboard tab on open.
      _entries = [];
    }
  }

  Future<void> _save() async {
    if (_dir == null) return;
    final list = _entries
        .map((e) => {
              'id': e.id,
              'text': e.text,
              'timestamp': e.timestamp,
              'pinned': e.pinned,
            })
        .toList();
    await _file.writeAsString(jsonEncode(list));
  }

  /// Pinned first, then most-recent — mirrors the desktop server's own
  /// ordering (see clipboard_history.py's ClipboardStore.search), since
  /// there's no server to ask while offline.
  List<ClipboardEntry> localEntries({String query = ''}) {
    var list = List<ClipboardEntry>.from(_entries);
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      list = list.where((e) => e.text.toLowerCase().contains(q)).toList();
    }
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.timestamp.compareTo(a.timestamp);
    });
    return list;
  }

  /// Overwrites the cache with a fresh fetch from the desktop.
  Future<void> replaceFromServer(List<ClipboardEntry> serverEntries) async {
    await ensureReady();
    _entries = serverEntries;
    await _save();
  }

  Future<void> clear() async {
    await ensureReady();
    _entries = [];
    await _save();
  }
}
