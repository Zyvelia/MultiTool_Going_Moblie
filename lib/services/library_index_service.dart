import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/song.dart';
import 'api_service.dart';

enum LibraryIndexEvent { syncStarted, syncProgress, syncFinished, syncFailed }

class LibraryIndexState {
  final LibraryIndexEvent event;
  final int done;
  final int total;
  final String? error;
  const LibraryIndexState(this.event, {this.done = 0, this.total = 0, this.error});
}

/// Persists the full song library metadata (title/artist/album/duration/size)
/// to a local JSON file so search and artist-browse work without the hub.
///
/// Audio files stay on the desktop. This only caches the index — roughly
/// 1–2 KB per 100 songs, so even a 10,000-song library is ~200 KB.
///
/// File: <documents>/offline_music/library_index.json
/// Format: {"version":1,"synced":"<iso8601>","songs":[{...},...]}
///
/// A sync pages through /api/songs 200 at a time. It replaces the index
/// atomically (write to .tmp, rename) so a partial sync never corrupts
/// the stored index. The previous index stays readable the entire time
/// a sync is in progress.
class LibraryIndexService {
  LibraryIndexService._internal();
  static final LibraryIndexService instance = LibraryIndexService._internal();

  final StreamController<LibraryIndexState> _events =
      StreamController<LibraryIndexState>.broadcast();
  Stream<LibraryIndexState> get events => _events.stream;

  Directory? _dir;
  List<Song> _songs = [];
  DateTime? _lastSynced;
  bool _initialized = false;
  Future<void>? _initFuture;
  bool _syncing = false;

  /// True once [ensureReady] has resolved and [songs] / [lastSynced] are
  /// populated from disk (they may be empty if never synced before).
  bool get isReady => _initialized;
  bool get isSyncing => _syncing;

  /// Full metadata list from the last successful sync. Empty before the
  /// first sync completes.
  List<Song> get songs => List.unmodifiable(_songs);
  DateTime? get lastSynced => _lastSynced;
  int get count => _songs.length;

  Future<void> ensureReady() {
    return _initFuture ??= _init();
  }

  Future<void> _init() async {
    final docs = await getApplicationDocumentsDirectory();
    _dir = Directory('${docs.path}/offline_music');
    await _dir!.create(recursive: true);
    await _loadIndex();
    _initialized = true;
  }

  File get _indexFile => File('${_dir!.path}/library_index.json');
  File get _indexTmp => File('${_dir!.path}/library_index.json.tmp');

  Future<void> _loadIndex() async {
    try {
      final f = _indexFile;
      if (!await f.exists()) return;
      final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final list = (raw['songs'] as List? ?? [])
          .map((s) {
            try {
              return Song.fromJson(s as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<Song>()
          .toList();
      _songs = list;
      _lastSynced = DateTime.tryParse(raw['synced'] as String? ?? '');
    } catch (_) {
      // Corrupt index — just start fresh; next sync will rebuild it.
    }
  }

  /// Downloads the full song list from [api] and persists it.
  /// No-op if already syncing. Fires [LibraryIndexEvent]s on [events].
  Future<void> sync(ApiService api) async {
    await ensureReady();
    if (_syncing) return;
    _syncing = true;
    _events.add(const LibraryIndexState(LibraryIndexEvent.syncStarted));

    final all = <Song>[];
    var offset = 0;
    const pageSize = 200;

    try {
      while (true) {
        final result = await api.fetchSongs(
          offset: offset,
          limit: pageSize,
          timeout: const Duration(seconds: 15),
        );
        all.addAll(result.songs);
        offset += result.songs.length;
        _events.add(LibraryIndexState(
          LibraryIndexEvent.syncProgress,
          done: all.length,
          // fetchSongs returns total from the server; use it once we have it
          total: result.total > 0 ? result.total : all.length,
        ));
        if (!result.hasMore || result.songs.isEmpty) break;
      }

      // Atomic write
      final now = DateTime.now();
      final payload = jsonEncode({
        'version': 1,
        'synced': now.toIso8601String(),
        'songs': all.map(_songToJson).toList(),
      });
      await _indexTmp.writeAsString(payload);
      if (await _indexFile.exists()) await _indexFile.delete();
      await _indexTmp.rename(_indexFile.path);

      _songs = all;
      _lastSynced = now;
      _events.add(LibraryIndexState(
        LibraryIndexEvent.syncFinished,
        done: all.length,
        total: all.length,
      ));
    } catch (e) {
      try {
        if (await _indexTmp.exists()) await _indexTmp.delete();
      } catch (_) {}
      _events.add(LibraryIndexState(
        LibraryIndexEvent.syncFailed,
        error: e.toString(),
      ));
    } finally {
      _syncing = false;
    }
  }

  /// Search the local index. Matches against title, artist, and album.
  /// Returns all songs when [query] is blank.
  List<Song> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return List.unmodifiable(_songs);
    return _songs
        .where((s) =>
            s.title.toLowerCase().contains(q) ||
            s.artist.toLowerCase().contains(q) ||
            s.album.toLowerCase().contains(q))
        .toList();
  }

  /// Returns a sorted artist → songs map from the local index,
  /// optionally filtered by [query].
  Map<String, List<Song>> artistMap({String query = ''}) {
    final source = query.isEmpty ? _songs : search(query);
    final map = <String, List<Song>>{};
    for (final song in source) {
      final artist = song.artist.isNotEmpty ? song.artist : 'Unknown Artist';
      (map[artist] ??= []).add(song);
    }
    return Map.fromEntries(
      map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  static Map<String, dynamic> _songToJson(Song s) => {
        'id': s.id,
        'title': s.title,
        'artist': s.artist,
        'album': s.album,
        'duration': s.duration,
        'size': s.size,
      };
}
