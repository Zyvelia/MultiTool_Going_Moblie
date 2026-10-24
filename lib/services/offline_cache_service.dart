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
  'audio/mp3': 'mp3',
  'audio/x-mp3': 'mp3',
  'audio/flac': 'flac',
  'audio/x-flac': 'flac',
  'audio/wav': 'wav',
  'audio/x-wav': 'wav',
  'audio/ogg': 'ogg',
  'application/ogg': 'ogg',
  'audio/opus': 'opus',
  'audio/mp4': 'm4a',
  'audio/x-m4a': 'm4a',
  'audio/aac': 'aac',
  'audio/x-aiff': 'aiff',
  'audio/x-ms-wma': 'wma',
  'audio/aiff': 'aiff',
  'audio/x-matroska': 'mka',
  'audio/webm': 'webm',
  'audio/3gpp': '3gp',
  'audio/amr': 'amr',
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

/// iPhone AVPlayer opens these. FLAC, OGG, Opus, and WMA come back as
/// error -11800 ("The operation could not be completed") even when the
/// file extension is right.
const Set<String> _iosPlayable = {
  'mp3', 'm4a', 'aac', 'wav', 'aiff', 'aif', 'caf', 'mp4', 'm4b', '3gp', 'amr',
};

bool phoneCanDecode(String ext) {
  if (!Platform.isIOS) return true;
  return _iosPlayable.contains(ext.toLowerCase());
}

/// Extension implied by the first bytes, or null when they are not audio.
String? sniffAudioExt(List<int> b) {
  if (b.length < 4) return null;
  if (b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33) return 'mp3';
  if (b[0] == 0x66 && b[1] == 0x4C && b[2] == 0x61 && b[3] == 0x43) {
    return 'flac';
  }
  if (b[0] == 0x4F && b[1] == 0x67 && b[2] == 0x67 && b[3] == 0x53) {
    return 'ogg';
  }
  if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46) {
    if (b.length >= 12 &&
        b[8] == 0x57 &&
        b[9] == 0x41 &&
        b[10] == 0x56 &&
        b[11] == 0x45) {
      return 'wav';
    }
    return null;
  }
  if (b[0] == 0x46 && b[1] == 0x4F && b[2] == 0x52 && b[3] == 0x4D) {
    return 'aiff';
  }
  if (b.length >= 8 &&
      b[4] == 0x66 &&
      b[5] == 0x74 &&
      b[6] == 0x79 &&
      b[7] == 0x70) {
    return 'm4a';
  }
  if (b[0] == 0x30 && b[1] == 0x26 && b[2] == 0xB2 && b[3] == 0x75) {
    return 'wma';
  }
  if (b[0] == 0xFF && (b[1] & 0xE0) == 0xE0) {
    final layer = (b[1] >> 1) & 0x03;
    if (layer == 0) return 'aac';
    return 'mp3';
  }
  return null;
}

bool _isJpegOrPng(List<int> b) {
  if (b.length < 4) return false;
  if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return true;
  return b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
}

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
  final String? artExt;
  final DateTime downloadedAt;

  _ManifestEntry({
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.size,
    required this.ext,
    this.artExt,
    required this.downloadedAt,
  });

  factory _ManifestEntry.fromJson(Map<String, dynamic> j) => _ManifestEntry(
        title: j['title'] as String? ?? '',
        artist: j['artist'] as String? ?? '',
        album: j['album'] as String? ?? '',
        duration: (j['duration'] as num?)?.toInt() ?? 0,
        size: (j['size'] as num?)?.toInt() ?? 0,
        ext: j['ext'] as String? ?? 'mp3',
        artExt: j['artExt'] as String?,
        downloadedAt:
            DateTime.tryParse(j['downloadedAt'] as String? ?? '') ??
                DateTime.now(),
      );

  _ManifestEntry copyWith({String? ext}) => _ManifestEntry(
        title: title,
        artist: artist,
        album: album,
        duration: duration,
        size: size,
        ext: ext ?? this.ext,
        artExt: artExt,
        downloadedAt: downloadedAt,
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'artist': artist,
        'album': album,
        'duration': duration,
        'size': size,
        'ext': ext,
        if (artExt != null) 'artExt': artExt,
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
  final Set<int> _replacing = {};
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

  void _saveManifestSync() {
    final map = _manifest.map((id, e) => MapEntry('$id', e.toJson()));
    _manifestFile.writeAsStringSync(jsonEncode(map));
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

  File? localArtFile(int songId) {
    final e = _manifest[songId];
    if (e == null || e.artExt == null || _dir == null) return null;
    final f = File('${_dir!.path}/files/$songId.cover.${e.artExt}');
    return f.existsSync() ? f : null;
  }

  Uri? artUriFor(int songId) {
    final f = localArtFile(songId);
    if (f == null) return null;
    try {
      final raf = f.openSync();
      final List<int> head;
      try {
        head = raf.readSync(16);
      } finally {
        raf.closeSync();
      }
      // A cover the phone cannot decode has taken down the whole item
      // on iOS. Only jpeg and png are handed to the player.
      if (!_isJpegOrPng(head)) return null;
    } catch (_) {
      return null;
    }
    return Uri.file(f.path);
  }

  /// Local file when this phone can actually decode it. Renames the file
  /// when the bytes disagree with the saved extension (AVPlayer trusts
  /// the extension and returns -11800 when they disagree). Returns null
  /// for a missing, tiny, or unsupported file so the caller can stream
  /// a converted copy instead.
  File? localPlayable(int songId) {
    final entry = _manifest[songId];
    final file = localFile(songId);
    if (entry == null || file == null || !file.existsSync()) return null;
    if (file.lengthSync() < 64) return null;

    var ext = entry.ext;
    File play = file;
    try {
      final raf = file.openSync();
      final List<int> head;
      try {
        head = raf.readSync(16);
      } finally {
        raf.closeSync();
      }
      final sniffed = sniffAudioExt(head);
      if (sniffed != null && sniffed != entry.ext && _dir != null) {
        final renamed = File('${_dir!.path}/files/$songId.$sniffed');
        if (renamed.path != file.path) {
          if (renamed.existsSync()) renamed.deleteSync();
          file.renameSync(renamed.path);
        }
        _manifest[songId] = entry.copyWith(ext: sniffed);
        _saveManifestSync();
        ext = sniffed;
        play = renamed;
      } else if (sniffed != null) {
        ext = sniffed;
      }
    } catch (_) {
      ext = entry.ext;
      play = file;
    }
    if (!phoneCanDecode(ext)) return null;
    return play.existsSync() ? play : null;
  }

  /// Replaces a download this phone cannot play. The old file stays until
  /// the new one has been saved, so a failed conversion does not wipe it.
  Future<void> replaceForPhone(Song song, ApiService api) async {
    await ensureReady();
    if (_replacing.contains(song.id) || _downloading.contains(song.id)) return;
    _replacing.add(song.id);
    final old = localFile(song.id);
    final oldEntry = _manifest[song.id];
    try {
      if (oldEntry != null) {
        _manifest.remove(song.id);
        await _saveManifest();
      }
      await download(song, api, forceTranscode: true);
      if (isCached(song.id)) {
        final current = localFile(song.id);
        if (old != null &&
            current != null &&
            old.path != current.path &&
            await old.exists()) {
          try {
            await old.delete();
          } catch (_) {}
        }
      } else if (oldEntry != null && old != null && await old.exists()) {
        _manifest[song.id] = oldEntry;
        await _saveManifest();
      }
    } finally {
      _replacing.remove(song.id);
    }
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

  Future<void> download(Song song, ApiService api, {bool forceTranscode = false}) async {
    await ensureReady();
    if (_manifest.containsKey(song.id) || _downloading.contains(song.id)) {
      return;
    }
    _downloading.add(song.id);
    _events.add(CacheEvent(CacheEventType.started, songId: song.id));

    final opened = <http.Client>[http.Client()];
    var active = opened.first;
    _clients[song.id] = active;
    File? tmp;
    try {
      var transcode = forceTranscode;
      var round = 0;
      while (round < 2) {
        round++;
        final resp = await _openAudio(
          active,
          api,
          song.id,
          transcode: transcode,
          force: forceTranscode,
        );
        if (resp.statusCode != 200) {
          throw Exception(_downloadStatusMessage(resp.statusCode));
        }
        final mimeExt = transcode ? 'm4a' : _mimeExtOf(resp);
        if (!transcode &&
            Platform.isIOS &&
            mimeExt != null &&
            !phoneCanDecode(mimeExt)) {
          // Stop the original body so a FLAC is not saved, then ask the
          // PC for an m4a instead.
          try {
            await resp.stream
                .listen((_) {}, onError: (_) {}, cancelOnError: true)
                .cancel();
          } catch (_) {}
          active = _swapClient(opened, song.id);
          transcode = true;
          continue;
        }

        final saved = await _writeAudio(
          song,
          resp,
          total: transcode ? 0 : (resp.contentLength ?? song.size),
        );
        if (saved == null) return;
        tmp = saved.tmp;

        final ext = saved.sniffed ?? mimeExt;
        final phoneRejected = Platform.isIOS && (ext == null || !phoneCanDecode(ext));
        if (!transcode && phoneRejected) {
          if (await saved.tmp.exists()) await saved.tmp.delete();
          tmp = null;
          active = _swapClient(opened, song.id);
          transcode = true;
          continue;
        }
        if (ext == null) {
          throw Exception('The PC did not send an audio file for that song.');
        }
        if (phoneRejected) {
          throw Exception(
            'This phone cannot play that song until the PC converts it. Install ffmpeg on the PC, then download it again.',
          );
        }
        if (transcode &&
            saved.received < (song.duration > 0 ? song.duration * 8000 : 4096)) {
          throw Exception(
            'The converted download was cut off. Try it again while the PC is on Go Live.',
          );
        }
        if (!transcode &&
            saved.expected != null &&
            saved.expected! > 0 &&
            saved.received != saved.expected) {
          throw Exception(
            'The download was cut off before the song finished. Try it again while the PC is on Go Live.',
          );
        }

        await _commitDownload(song, api, saved.tmp, saved.received, ext, active);
        return;
      }
      throw Exception('The PC did not send an audio file for that song.');
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
      for (final c in opened) {
        _closeQuiet(c);
      }
    }
  }

  http.Client _swapClient(List<http.Client> opened, int songId) {
    _closeQuiet(opened.last);
    final next = http.Client();
    opened.add(next);
    _clients[songId] = next;
    return next;
  }

  void _closeQuiet(http.Client client) {
    try {
      client.close();
    } catch (_) {}
  }

  String? _mimeExtOf(http.StreamedResponse resp) {
    final contentType =
        resp.headers['content-type']?.split(';').first.trim().toLowerCase();
    return _extForMime[contentType];
  }

  String _downloadStatusMessage(int status) {
    if (status == 415) {
      return 'The PC could not convert this song for the phone. Install ffmpeg on the PC, then try the download again.';
    }
    return 'server returned $status';
  }

  Future<http.StreamedResponse> _openAudio(
    http.Client client,
    ApiService api,
    int songId, {
    required bool transcode,
    bool force = false,
  }) {
    final req = http.Request(
      'GET',
      Uri.parse(api.streamUrl(songId, transcode: transcode, force: force && transcode)),
    );
    return client.send(req).timeout(
      transcode ? const Duration(minutes: 8) : const Duration(seconds: 20),
    );
  }

  Future<_SavedAudio?> _writeAudio(
    Song song,
    http.StreamedResponse resp, {
    required int total,
  }) async {
    final tmp = File('${_dir!.path}/files/.tmp_${song.id}');
    final sink = tmp.openWrite();
    var received = 0;
    List<int>? head;
    try {
      await for (final chunk in resp.stream) {
        if (_cancelled.contains(song.id)) break;
        head ??= chunk.length > 16 ? chunk.sublist(0, 16) : List<int>.from(chunk);
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
      return null;
    }
    return _SavedAudio(
      tmp: tmp,
      received: received,
      expected: resp.contentLength,
      sniffed: sniffAudioExt(head ?? const []),
    );
  }

  Future<void> _commitDownload(
    Song song,
    ApiService api,
    File tmp,
    int received,
    String ext,
    http.Client client,
  ) async {
    final finalFile = File('${_dir!.path}/files/${song.id}.$ext');
    if (await finalFile.exists()) await finalFile.delete();
    await tmp.rename(finalFile.path);

    String? artExt;
    try {
      final artReq = http.Request('GET', Uri.parse(api.coverArtUrl(song.id)));
      final artResp = await client.send(artReq).timeout(const Duration(seconds: 8));
      if (artResp.statusCode == 200) {
        final artMime = artResp.headers['content-type']
            ?.split(';')
            .first
            .trim()
            .toLowerCase();
        artExt = _extForMime[artMime] ?? 'jpg';
        final artTmp = File('${_dir!.path}/files/.tmp_${song.id}.cover');
        final artSink = artTmp.openWrite();
        await artResp.stream.pipe(artSink);
        await artSink.close();
        final artFinal = File('${_dir!.path}/files/${song.id}.cover.$artExt');
        if (await artFinal.exists()) await artFinal.delete();
        await artTmp.rename(artFinal.path);
      }
    } catch (_) {
      artExt = null;
    }

    _manifest[song.id] = _ManifestEntry(
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: song.duration,
      size: received,
      ext: ext,
      artExt: artExt,
      downloadedAt: DateTime.now(),
    );
    await _saveManifest();
    _events.add(CacheEvent(CacheEventType.completed, songId: song.id));
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

class _SavedAudio {
  final File tmp;
  final int received;
  final int? expected;
  final String? sniffed;
  const _SavedAudio({
    required this.tmp,
    required this.received,
    required this.expected,
    required this.sniffed,
  });
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
