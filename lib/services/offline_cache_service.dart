import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';
import 'api_service.dart';

/// Content-Type -> file extension, for naming files written to the
/// offline cache. just_audio's file-based sources generally sniff
/// content rather than trust the extension, but iOS's AVPlayer backend
/// leans on it more, so this is worth getting right rather than always
/// writing `.mp3`. Mirrors the server's own `_MIME_OVERRIDES` in
/// modules/media_player/web_server.py, just inverted.
const Map<String, String> _extForMime = {
  'audio/mpeg': 'mp3',
  'audio/flac': 'flac',
  'audio/wav': 'wav',
  'audio/x-wav': 'wav',
  'audio/ogg': 'ogg',
  'audio/opus': 'opus',
  'audio/mp4': 'm4a',
  'audio/aac': 'aac',
  'audio/x-ms-wma': 'wma',
  'audio/aiff': 'aiff',
  'audio/x-matroska': 'mka',
  'audio/webm': 'webm',
  'audio/3gpp': '3gp',
  'audio/amr': 'amr',
};

enum CacheEventType {
  started,
  progress,
  completed,
  removed,
  error,
  cleared,
  // Batch ("download all") events, distinct from the per-song ones above
  // so LibraryScreen can drive an overall progress banner without trying
  // to infer batch membership from individual song events.
  batchStarted,
  batchProgress,
  batchFinished,
  batchCancelled,
}

class CacheEvent {
  final CacheEventType type;
  final int? songId;
  final double? progress; // 0..1, or negative when total size is unknown
  final String? error;
  final int? batchDone;
  final int? batchTotal;
  const CacheEvent(
    this.type, {
    this.songId,
    this.progress,
    this.error,
    this.batchDone,
    this.batchTotal,
  });
}

class _ManifestEntry {
  final String title;
  final String artist;
  final String album;
  final int duration;
  final int size;
  final String ext;
  final DateTime downloadedAt;

  _ManifestEntry({
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.size,
    required this.ext,
    required this.downloadedAt,
  });

  factory _ManifestEntry.fromJson(Map<String, dynamic> j) => _ManifestEntry(
        title: j['title'] as String? ?? '',
        artist: j['artist'] as String? ?? '',
        album: j['album'] as String? ?? '',
        duration: (j['duration'] as num?)?.toInt() ?? 0,
        size: (j['size'] as num?)?.toInt() ?? 0,
        ext: j['ext'] as String? ?? 'mp3',
        downloadedAt:
            DateTime.tryParse(j['downloadedAt'] as String? ?? '') ??
                DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'artist': artist,
        'album': album,
        'duration': duration,
        'size': size,
        'ext': ext,
        'downloadedAt': downloadedAt.toIso8601String(),
      };
}

/// Explicit, user-controlled offline storage for songs — separate from
/// (and takes priority over) the implicit per-play caching
/// LockCachingAudioSource already does in "This phone" mode. A song the
/// user has explicitly downloaded here:
///   - plays from a local file with zero network/data use, even in PC
///     mode's stream picker being irrelevant — this only affects phone
///     playback source selection in LibraryScreen._sourceFor.
///   - survives being evicted from just_audio's opportunistic stream
///     cache, and survives the app being fully offline (no server
///     reachable at all) — LibraryScreen falls back to
///     [downloadedSongs] for the song list itself in that case, not
///     just for playback.
///
/// Files live under the app's documents directory (survives app
/// restarts, not wiped by the OS under storage pressure the way a
/// cache directory can be) at `offline_music/files/<songId>.<ext>`,
/// indexed by a small JSON manifest at `offline_music/manifest.json`.
/// There's deliberately no automatic eviction/size cap here — "explicit"
/// cache management means the user decides what leaves, not an LRU
/// policy silently deleting something they downloaded on purpose.
class OfflineCacheService {
  OfflineCacheService._internal();
  static final OfflineCacheService instance = OfflineCacheService._internal();

  final StreamController<CacheEvent> _events =
      StreamController<CacheEvent>.broadcast();
  Stream<CacheEvent> get events => _events.stream;

  Directory? _dir;
  final Map<int, _ManifestEntry> _manifest = {};
  final Set<int> _downloading = {};
  final Set<int> _cancelled = {};
  final Map<int, http.Client> _clients = {};
  bool _initialized = false;
  Future<void>? _initFuture;

  /// Loads the manifest from disk. Safe to call repeatedly — later calls
  /// just await the same in-flight future or return immediately once
  /// done. Call this once (e.g. from LibraryScreen._init) before relying
  /// on [isCached]/[downloadedSongs] so they're not seeing an empty
  /// pre-load state.
  Future<void> ensureReady() {
    return _initFuture ??= _init();
  }

  Future<void> _init() async {
    final docs = await getApplicationDocumentsDirectory();
    _dir = Directory('${docs.path}/offline_music');
    await Directory('${_dir!.path}/files').create(recursive: true);
    await _loadManifest();
    _initialized = true;
  }

  File get _manifestFile => File('${_dir!.path}/manifest.json');

  Future<void> _loadManifest() async {
    try {
      final f = _manifestFile;
      if (!await f.exists()) return;
      final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      raw.forEach((key, value) {
        final id = int.tryParse(key);
        if (id == null) return;
        try {
          _manifest[id] = _ManifestEntry.fromJson(value as Map<String, dynamic>);
        } catch (_) {
          // One corrupt entry shouldn't take down the whole manifest.
        }
      });
    } catch (_) {
      // Corrupt/unreadable manifest — start fresh rather than crash the
      // library tab on open. Existing downloaded files just become
      // orphaned on disk; not worth reconciling automatically.
    }
  }

  Future<void> _saveManifest() async {
    final map = _manifest.map((id, e) => MapEntry('$id', e.toJson()));
    await _manifestFile.writeAsString(jsonEncode(map));
  }

  bool get isReady => _initialized;
  bool isCached(int songId) => _manifest.containsKey(songId);
  bool isDownloading(int songId) => _downloading.contains(songId);
  int get count => _manifest.length;
  int get totalBytes =>
      _manifest.values.fold<int>(0, (sum, e) => sum + e.size);

  /// Local file for a cached song. Only meaningful when [isCached] is
  /// true — callers shouldn't assume the file exists otherwise.
  File? localFile(int songId) {
    final e = _manifest[songId];
    if (e == null || _dir == null) return null;
    return File('${_dir!.path}/files/$songId.${e.ext}');
  }

  /// All explicitly-downloaded songs, sorted by title — used both by the
  /// Downloads management screen and as LibraryScreen's fallback song
  /// list when the desktop is completely unreachable.
  List<Song> get downloadedSongs {
    final list = _manifest.entries
        .map((e) => Song(
              id: e.key,
              title: e.value.title,
              artist: e.value.artist,
              album: e.value.album,
              duration: e.value.duration,
              size: e.value.size,
            ))
        .toList();
    list.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return list;
  }

  Future<void> download(Song song, ApiService api) async {
    await ensureReady();
    if (_manifest.containsKey(song.id) || _downloading.contains(song.id)) {
      return;
    }
    _downloading.add(song.id);
    _events.add(CacheEvent(CacheEventType.started, songId: song.id));

    final client = http.Client();
    _clients[song.id] = client;
    File? tmp;
    try {
      final req = http.Request('GET', Uri.parse(api.streamUrl(song.id)));
      final resp = await client.send(req).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        throw Exception('server returned ${resp.statusCode}');
      }
      final contentType =
          resp.headers['content-type']?.split(';').first.trim().toLowerCase();
      final ext = _extForMime[contentType] ?? 'mp3';
      final total = resp.contentLength ?? song.size;

      tmp = File('${_dir!.path}/files/.tmp_${song.id}');
      final sink = tmp.openWrite();
      var received = 0;
      try {
        await for (final chunk in resp.stream) {
          if (_cancelled.contains(song.id)) break;
          sink.add(chunk);
          received += chunk.length;
          _events.add(CacheEvent(
            CacheEventType.progress,
            songId: song.id,
            progress: total > 0 ? (received / total).clamp(0, 1) : -1,
          ));
        }
      } finally {
        await sink.close();
      }

      if (_cancelled.remove(song.id)) {
        if (await tmp.exists()) await tmp.delete();
        return;
      }

      final finalFile = File('${_dir!.path}/files/${song.id}.$ext');
      if (await finalFile.exists()) await finalFile.delete();
      await tmp.rename(finalFile.path);

      _manifest[song.id] = _ManifestEntry(
        title: song.title,
        artist: song.artist,
        album: song.album,
        duration: song.duration,
        size: received,
        ext: ext,
        downloadedAt: DateTime.now(),
      );
      await _saveManifest();
      _events.add(CacheEvent(CacheEventType.completed, songId: song.id));
    } catch (e) {
      try {
        if (tmp != null && await tmp.exists()) await tmp.delete();
      } catch (_) {}
      // A deliberate cancel closes the client, which surfaces here as a
      // stream error too — don't report that as a failure, cancelDownload
      // already told listeners about it.
      if (!_cancelled.remove(song.id)) {
        _events.add(CacheEvent(CacheEventType.error, songId: song.id, error: '$e'));
      }
    } finally {
      _downloading.remove(song.id);
      _clients.remove(song.id);
      client.close();
    }
  }

  bool _batchRunning = false;
  bool _batchCancelled = false;
  bool get isBatchRunning => _batchRunning;

  /// Downloads every song in [songs] that isn't already cached (or
  /// already mid-download), a handful at a time. Reuses [download] for
  /// each individual song, so per-song progress/error events fire exactly
  /// as they would for a manual tap — this just adds the overall
  /// batchStarted/batchProgress/batchFinished events on top for a
  /// "download all" progress banner. A no-op if a batch is already
  /// running or nothing needs downloading.
  Future<void> downloadAll(
    List<Song> songs,
    ApiService api, {
    int concurrency = 3,
  }) async {
    await ensureReady();
    if (_batchRunning) return;
    final pending =
        songs.where((s) => !isCached(s.id) && !isDownloading(s.id)).toList();
    if (pending.isEmpty) return;

    _batchRunning = true;
    _batchCancelled = false;
    final total = pending.length;
    var done = 0;
    _events.add(CacheEvent(CacheEventType.batchStarted, batchTotal: total));

    var next = 0;
    Future<void> worker() async {
      while (!_batchCancelled) {
        if (next >= pending.length) return;
        final song = pending[next++];
        if (!isCached(song.id) && !isDownloading(song.id)) {
          await download(song, api);
        }
        done++;
        _events.add(CacheEvent(
          CacheEventType.batchProgress,
          batchDone: done,
          batchTotal: total,
        ));
      }
    }

    await Future.wait(
      List.generate(concurrency.clamp(1, total), (_) => worker()),
    );

    _batchRunning = false;
    _events.add(CacheEvent(
      _batchCancelled ? CacheEventType.batchCancelled : CacheEventType.batchFinished,
      batchDone: done,
      batchTotal: total,
    ));
  }

  /// Stops a running [downloadAll] batch: no further songs are started,
  /// and whatever's currently mid-download (up to [concurrency] of them)
  /// is cancelled too, same as a manual per-song cancel.
  void cancelBatch() {
    if (!_batchRunning) return;
    _batchCancelled = true;
    for (final id in _downloading.toList()) {
      cancelDownload(id);
    }
  }

  void cancelDownload(int songId) {
    if (!_downloading.contains(songId)) return;
    _cancelled.add(songId);
    _clients[songId]?.close();
    _events.add(CacheEvent(CacheEventType.removed, songId: songId));
  }

  Future<void> remove(int songId) async {
    await ensureReady();
    cancelDownload(songId);
    final f = localFile(songId);
    _manifest.remove(songId);
    await _saveManifest();
    try {
      if (f != null && await f.exists()) await f.delete();
    } catch (_) {}
    _events.add(CacheEvent(CacheEventType.removed, songId: songId));
  }

  Future<void> clearAll() async {
    await ensureReady();
    for (final id in _downloading.toList()) {
      cancelDownload(id);
    }
    _manifest.clear();
    await _saveManifest();
    try {
      final filesDir = Directory('${_dir!.path}/files');
      if (await filesDir.exists()) {
        await filesDir.delete(recursive: true);
      }
      await filesDir.create(recursive: true);
    } catch (_) {}
    _events.add(const CacheEvent(CacheEventType.cleared));
  }
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var i = 0;
  var v = bytes.toDouble();
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v < 10 && i > 0 ? 1 : 0)} ${units[i]}';
}
