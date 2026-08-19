import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/now_playing.dart';
import '../models/server_profile.dart';
import '../models/song.dart';
import '../services/api_service.dart';
import '../services/connectivity_service.dart';
import '../services/offline_cache_service.dart';
import '../services/settings_service.dart';
import '../theme/app_colors.dart';
import '../widgets/mini_player.dart';
import '../widgets/pc_mini_player.dart';
import '../widgets/song_tile.dart';
import 'downloads_screen.dart';

enum _PlaySource { phone, pc }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _settings = SettingsService();
  ApiService? _api;
  ResolvedServer? _server;
  final _player = AudioPlayer();
  StreamSubscription<NetworkType>? _connectivitySub;
  NetworkType _networkType = NetworkType.other;
  bool _reconnecting = false;
  final _searchController = TextEditingController();
  Timer? _debounce;

  final List<Song> _songs = [];
  int _offset = 0;
  int _total = 0;
  bool _hasMore = false;
  bool _loading = false;
  bool _fetching = false;
  String? _error;
  String _query = '';

  int _currentIndex = -1;

  // "Phone" streams audio into this screen's own AudioPlayer and plays
  // locally. "PC" instead remote-controls the desktop app's own player
  // (audio comes out of the PC's speakers) via polling /api/now-playing
  // and posting to /api/control.
  _PlaySource _source = _PlaySource.phone;
  Timer? _pollTimer;
  NowPlaying? _nowPlaying;
  bool _sendingControl = false;

  int _midStreamRetries = 0;

  // Explicit offline cache — separate from (and takes priority over) the
  // implicit per-play caching LockCachingAudioSource does below. Progress
  // is keyed by song id; a song not present here and not [_cache.isCached]
  // is simply not downloaded.
  final _cache = OfflineCacheService.instance;
  StreamSubscription<CacheEvent>? _cacheSub;
  final Map<int, double> _downloadProgress = {};
  // "Download all" batch state, driven by OfflineCacheService's
  // batchStarted/batchProgress/batchFinished events (see _onCacheEvent).
  bool _batchActive = false;
  int _batchDone = 0;
  int _batchTotal = 0;
  bool _fetchingBatchList = false;
  // True when the song list currently on screen came from the offline
  // cache manifest rather than a live /api/songs response, because the
  // desktop was unreachable. Search is disabled in this state — the
  // cache has no search index, just whatever's downloaded.
  bool _offlineFallback = false;

  // Mirrors _songs 1:1. Giving the player an actual playlist (instead of
  // swapping in one isolated AudioSource per tap) is what lets
  // just_audio_background know there's a next/previous track to skip to —
  // it only shows those buttons when the player's own sequence has one.
  final _playlist = ConcatenatingAudioSource(children: []);
  bool _playlistAttached = false;

  @override
  void initState() {
    super.initState();
    _init();
    _initConnectivity();
    _cacheSub = _cache.events.listen(_onCacheEvent);
    // The playlist auto-advances on its own now (see _playlist above), so
    // the old "reload the next track when the current one completes"
    // handler that used to live here is gone — that manual setAudioSource
    // call from inside a processingStateStream listener was the actual
    // cause of the 1004 (ERROR_CODE_FAILED_RUNTIME_CHECK) bug.
    // Keep app state (highlighted row, mini player) in sync when a skip
    // comes from the lock screen / notification rather than in-app.
    _player.currentIndexStream.listen((index) {
      if (mounted && index != null && index != _currentIndex) {
        setState(() => _currentIndex = index);
      }
    });
    // The retry loop in _playIndex only covers a blip right as a track
    // starts. A Tailscale hiccup a few seconds into an already-playing
    // track (the more common case while out and about on cellular) comes
    // through here instead, as a stream error rather than a thrown
    // exception. Re-request the same track a couple of times before
    // treating it as a real failure.
    _player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        final index = _player.currentIndex;
        if (index == null || index < 0 || index >= _songs.length) return;
        // Local files don't recover by re-requesting a stream — retrying
        // would just wait on a dead Tailscale hop for nothing.
        if (_cache.isCached(_songs[index].id)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Playback failed: $e')),
            );
          }
          return;
        }
        if (_midStreamRetries >= 2) {
          _midStreamRetries = 0;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Playback dropped: $e')),
            );
          }
          return;
        }
        _midStreamRetries++;
        final resumeAt = _player.position;
        Future.delayed(Duration(milliseconds: 500 * _midStreamRetries), () async {
          if (!mounted) return;
          await _recoverTrack(index, resumeAt);
        });
      },
    );
  }

  // Swaps in a fresh LockCachingAudioSource at [index] (the cached item
  // may be stuck in a broken state after a dropped connection) and
  // resumes from where playback left off.
  Future<void> _recoverTrack(int index, Duration resumeAt) async {
    if (index < 0 || index >= _songs.length) return;
    final song = _songs[index];
    if (_cache.isCached(song.id)) {
      try {
        await _player.seek(resumeAt, index: index);
        await _player.play();
        _midStreamRetries = 0;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Playback failed: $e')),
          );
        }
      }
      return;
    }
    try {
      await _playlist.removeAt(index);
      await _playlist.insert(index, _sourceFor(song));
      await _player.seek(resumeAt, index: index);
      await _player.play();
      _midStreamRetries = 0;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playback failed: $e')),
        );
      }
    }
  }

  Future<void> _init() async {
    await _cache.ensureReady();
    if (!_playlistAttached) {
      await _player.setAudioSource(_playlist);
      _playlistAttached = true;
    }

    // Show downloaded tracks immediately so the tab isn't empty while we
    // wait to find out whether the desktop is reachable.
    if (_cache.count > 0) {
      await _showCachedLibrary(preservePlayback: false);
    }

    final net = await ConnectivityService.instance.current();
    if (mounted) setState(() => _networkType = net);

    if (net == NetworkType.offline) {
      // Don't probe Tailscale / wait on /api/songs — we're offline.
      unawaited(_resolveServer(skipProbe: true));
      if (_cache.count == 0) await _showCachedLibrary();
      return;
    }

    await _connectAndLoadLive();
  }

  Future<void> _resolveServer({bool skipProbe = false}) async {
    final server = await _settings.resolveMusicServer(skipProbe: skipProbe);
    if (!mounted || server == null) return;
    setState(() {
      _server = server;
      _api = ApiService(server.baseUrl);
    });
  }

  Future<void> _connectAndLoadLive() async {
    await _resolveServer();
    if (!mounted || _api == null) return;
    await _loadSongs(reset: true);
  }

  /// Replace (or append to) the on-screen list + player playlist together,
  /// keeping the current track playing across a live <-> offline swap.
  Future<void> _applySongList(
    List<Song> songs, {
    required bool reset,
    int? total,
    bool hasMore = false,
    bool offlineFallback = false,
    bool preservePlayback = true,
  }) async {
    final playingId = preservePlayback &&
            _currentIndex >= 0 &&
            _currentIndex < _songs.length
        ? _songs[_currentIndex].id
        : null;
    final wasPlaying = preservePlayback && _player.playing;
    final position = _player.position;

    if (!_playlistAttached) {
      await _player.setAudioSource(_playlist);
      _playlistAttached = true;
    }

    if (reset) await _playlist.clear();
    if (songs.isNotEmpty) {
      await _playlist.addAll(songs.map(_sourceFor).toList());
    }
    if (!mounted) return;

    setState(() {
      if (reset) {
        _songs
          ..clear()
          ..addAll(songs);
        _offset = songs.length;
      } else {
        _songs.addAll(songs);
        _offset += songs.length;
      }
      _total = total ?? _songs.length;
      _hasMore = hasMore;
      _loading = false;
      _offlineFallback = offlineFallback;
      _error = null;
      _reconnecting = false;
    });

    if (reset && playingId != null) {
      final newIndex = _songs.indexWhere((s) => s.id == playingId);
      if (newIndex >= 0) {
        try {
          await _player.seek(position, index: newIndex);
          if (wasPlaying) await _player.play();
        } catch (_) {}
      }
    }
  }

  Future<void> _showCachedLibrary({bool preservePlayback = true}) async {
    await _cache.ensureReady();
    var list = _cache.downloadedSongs;
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((s) =>
              s.title.toLowerCase().contains(q) ||
              s.artist.toLowerCase().contains(q) ||
              s.album.toLowerCase().contains(q))
          .toList();
    }
    if (_cache.count == 0) {
      if (mounted) {
        setState(() {
          _offlineFallback = true;
          _loading = false;
          _reconnecting = false;
          _hasMore = false;
          if (_songs.isEmpty) {
            _error = 'Offline and nothing downloaded yet.';
          }
        });
      }
      return;
    }
    await _applySongList(
      list,
      reset: true,
      offlineFallback: true,
      preservePlayback: preservePlayback,
    );
  }

  // Watches for Wi-Fi/cellular/offline transitions. This doesn't touch
  // playback directly — LockCachingAudioSource + the retry logic below
  // already ride out a drop mid-track — it's specifically for the
  // "connection came back after being offline" case: re-resolve which
  // server answers fastest (private vs public may have flipped after a
  // network change) and refresh the library/now-playing state instead
  // of silently sitting on stale data.
  void _initConnectivity() {
    ConnectivityService.instance.current().then((t) {
      if (mounted) setState(() => _networkType = t);
    });
    _connectivitySub = ConnectivityService.instance.onChange.listen((type) async {
      final wasOffline = _networkType == NetworkType.offline;
      if (mounted) setState(() => _networkType = type);

      if (type == NetworkType.offline) {
        if (_source == _PlaySource.pc) _setSource(_PlaySource.phone);
        if (!_offlineFallback) await _showCachedLibrary();
        return;
      }
      if (!wasOffline) return; // only act on offline -> back-online edges

      setState(() => _reconnecting = true);
      final server = await _settings.resolveMusicServer();
      if (!mounted) return;
      if (server != null && server.baseUrl != _server?.baseUrl) {
        setState(() {
          _server = server;
          _api = ApiService(server.baseUrl);
        });
      } else if (server != null && _api == null) {
        setState(() {
          _server = server;
          _api = ApiService(server.baseUrl);
        });
      }
      await _loadSongs(reset: true);
      if (_source == _PlaySource.pc) await _pollNowPlaying();
      if (mounted) setState(() => _reconnecting = false);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pollTimer?.cancel();
    _connectivitySub?.cancel();
    _cacheSub?.cancel();
    _player.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onCacheEvent(CacheEvent evt) {
    if (!mounted) return;
    setState(() {
      switch (evt.type) {
        case CacheEventType.progress:
          if (evt.songId != null) _downloadProgress[evt.songId!] = evt.progress ?? -1;
          break;
        case CacheEventType.started:
          if (evt.songId != null) _downloadProgress[evt.songId!] = -1;
          break;
        case CacheEventType.completed:
        case CacheEventType.removed:
          if (evt.songId != null) _downloadProgress.remove(evt.songId);
          break;
        case CacheEventType.error:
          if (evt.songId != null) _downloadProgress.remove(evt.songId);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download failed: ${evt.error}')),
          );
          break;
        case CacheEventType.cleared:
          _downloadProgress.clear();
          break;
        case CacheEventType.batchStarted:
          _batchActive = true;
          _batchDone = 0;
          _batchTotal = evt.batchTotal ?? 0;
          break;
        case CacheEventType.batchProgress:
          _batchDone = evt.batchDone ?? _batchDone;
          _batchTotal = evt.batchTotal ?? _batchTotal;
          break;
        case CacheEventType.batchFinished:
        case CacheEventType.batchCancelled:
          _batchActive = false;
          if (evt.type == CacheEventType.batchFinished && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Downloaded ${evt.batchDone ?? 0} songs')),
            );
          }
          break;
      }
    });
  }

  /// Kicks off downloading every song matching the current search across
  /// the whole library, not just the page(s) scrolled into view — the
  /// list on screen is paginated 100 at a time, so this pages through
  /// /api/songs itself first to build the full set.
  Future<void> _downloadAllTapped() async {
    if (_batchActive) {
      _cache.cancelBatch();
      return;
    }
    if (_api == null || _fetchingBatchList) return;

    final wifiOnly = await _settings.getMusicWifiOnlyDownloads();
    final metered = ConnectivityService.instance.isLikelyMetered(_networkType);
    if (wifiOnly && metered) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Downloads are Wi-Fi only — connect to Wi-Fi, or turn that '
              'off in Settings, to download over this connection.',
            ),
          ),
        );
      }
      return;
    }

    setState(() => _fetchingBatchList = true);
    List<Song> all;
    try {
      all = await _fetchAllMatchingSongs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load full song list: $e')),
        );
      }
      setState(() => _fetchingBatchList = false);
      return;
    }
    setState(() => _fetchingBatchList = false);

    final pending = all.where((s) => !_cache.isCached(s.id)).toList();
    if (pending.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Everything matching is already downloaded')),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Download all songs?', style: TextStyle(color: Colors.white)),
        content: Text(
          _query.isEmpty
              ? 'This downloads all ${pending.length} songs not already '
                  'saved to this device.'
              : 'This downloads ${pending.length} songs matching '
                  '"$_query" that aren\'t already saved to this device.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    if (confirmed != true || _api == null) return;
    _cache.downloadAll(pending, _api!);
  }

  /// Pages through /api/songs with the current search query until
  /// exhausted. Separate from the incremental _songs/_offset state used
  /// for on-screen scrolling — this always starts from offset 0 and
  /// doesn't touch that state.
  Future<List<Song>> _fetchAllMatchingSongs() async {
    final all = <Song>[];
    var offset = 0;
    while (true) {
      final result =
          await _api!.fetchSongs(query: _query, offset: offset, limit: 200);
      all.addAll(result.songs);
      offset += result.songs.length;
      if (!result.hasMore || result.songs.isEmpty) break;
    }
    return all;
  }

  SongCacheState _cacheStateFor(int songId) {
    if (_downloadProgress.containsKey(songId)) return SongCacheState.downloading;
    if (_cache.isCached(songId)) return SongCacheState.cached;
    return SongCacheState.none;
  }

  Future<void> _onCacheIconTap(Song song) async {
    final state = _cacheStateFor(song.id);
    if (state == SongCacheState.cached) {
      await _cache.remove(song.id);
      return;
    }
    if (state == SongCacheState.downloading) {
      _cache.cancelDownload(song.id);
      return;
    }
    if (_api == null) return;

    final wifiOnly = await _settings.getMusicWifiOnlyDownloads();
    final metered = ConnectivityService.instance.isLikelyMetered(_networkType);
    if (wifiOnly && metered) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Downloads are Wi-Fi only — connect to Wi-Fi, or turn that '
              'off in Settings, to download over this connection.',
            ),
          ),
        );
      }
      return;
    }
    _cache.download(song, _api!);
  }

  Future<void> _loadSongs({bool reset = false}) async {
    if (_api == null || _fetching) return;

    // OS already knows there's no interface — don't sit on HTTP timeouts.
    if (reset && _networkType == NetworkType.offline) {
      await _showCachedLibrary();
      return;
    }

    final hadSongs = _songs.isNotEmpty;
    _fetching = true;
    setState(() {
      _error = null;
      if (hadSongs && reset) {
        _reconnecting = true;
      } else if (!hadSongs) {
        _loading = true;
      }
    });

    try {
      final result = await _api!.fetchSongs(
        query: _query,
        offset: reset ? 0 : _offset,
        limit: 100,
        timeout: reset
            ? const Duration(seconds: 2)
            : const Duration(seconds: 10),
      );
      await _applySongList(
        result.songs,
        reset: reset,
        total: result.total,
        hasMore: result.hasMore,
        offlineFallback: false,
      );
    } catch (e) {
      if (reset) {
        await _showCachedLibrary();
        if (mounted && _songs.isEmpty) {
          setState(() {
            _error = 'Could not load library: $e';
            _loading = false;
            _reconnecting = false;
          });
        }
      } else if (mounted) {
        setState(() {
          _error = 'Could not load library: $e';
          _loading = false;
        });
      }
    } finally {
      _fetching = false;
    }
  }

  // LockCachingAudioSource streams like a normal URL source on first play,
  // but writes what it downloads to a local cache file as it goes — so
  // replaying the same song (even with a flaky Tailscale connection) reads
  // from disk instead of re-streaming. The MediaItem tag is what shows up
  // on the lock screen / notification via just_audio_background, and
  // (now that tracks live in a real playlist) is also what tells it
  // there's a next/previous item to show skip buttons for.
  AudioSource _sourceFor(Song song) {
    final tag = MediaItem(
      id: song.id.toString(),
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: song.duration > 0 ? Duration(seconds: song.duration) : null,
    );

    // Explicitly downloaded songs play straight from disk — no network,
    // no dependence on the desktop being reachable, and it's what makes
    // the offline-fallback song list above actually playable rather than
    // just browsable. Only reachable songs (from a live /api/songs
    // response, i.e. _api != null) fall through to network streaming.
    final local = _cache.isCached(song.id) ? _cache.localFile(song.id) : null;
    if (local != null) {
      return AudioSource.file(local.path, tag: tag);
    }
    return LockCachingAudioSource(
      Uri.parse(_api!.streamUrl(song.id)),
      tag: tag,
    );
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _query = value);
      if (_offlineFallback || _networkType == NetworkType.offline) {
        _showCachedLibrary();
      } else {
        _loadSongs(reset: true);
      }
    });
  }

  void _setSource(_PlaySource source) {
    if (source == _source) return;
    setState(() => _source = source);
    if (source == _PlaySource.pc) {
      // Only one place should be making sound at a time.
      _player.pause();
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollNowPlaying();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _pollNowPlaying());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollNowPlaying() async {
    if (_api == null) return;
    try {
      final np = await _api!.nowPlaying();
      if (mounted) setState(() => _nowPlaying = np);
    } catch (_) {
      // Desktop unreachable for a beat — keep showing the last known
      // state rather than flashing an error on every missed poll.
    }
  }

  Future<void> _sendControl(String action, {int? songId, double? value}) async {
    if (_api == null || _sendingControl) return;
    _sendingControl = true;
    try {
      await _api!.control(action, songId: songId, value: value);
      await _pollNowPlaying();
    } on ControlException catch (e) {
      // Refresh state regardless — a transient failure (dropped response
      // on the Tailscale hop) usually still means the command landed on
      // the PC, so the next poll shows the real, current state.
      await _pollNowPlaying();
      if (mounted && !e.transient) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PC control failed: ${e.message}')),
        );
      }
    } catch (e) {
      await _pollNowPlaying();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PC control failed: $e')),
        );
      }
    } finally {
      _sendingControl = false;
    }
  }

  Future<void> _playIndex(int index) async {
    if (index < 0 || index >= _songs.length) return;
    final local = _cache.isCached(_songs[index].id);

    Future<void> start() async {
      await _player.seek(Duration.zero, index: index);
      await _player.play();
      _midStreamRetries = 0;
    }

    // Downloaded tracks are on disk — don't burn time retrying a stream.
    if (local) {
      try {
        await start();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Playback failed: $e')),
          );
        }
      }
      return;
    }

    if (_api == null) return;

    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await start();
        return;
      } catch (e) {
        if (attempt == maxAttempts) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Playback failed: $e')),
            );
          }
          return;
        }
        await Future.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
  }

  void _playNext() {
    if (_player.hasNext) _player.seekToNext();
  }

  void _playPrev() {
    if (_player.hasPrevious) _player.seekToPrevious();
  }

  void _onSongTap(int index) {
    if (_source == _PlaySource.phone || _offlineFallback) {
      _playIndex(index);
    } else {
      _sendControl('play_song', songId: _songs[index].id);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_api == null && _songs.isEmpty && !_offlineFallback) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Set your Tailscale hostname or public music server URL in '
            'Settings first.',
            style: TextStyle(color: Colors.white54),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final activeSongId =
        _source == _PlaySource.pc ? _nowPlaying?.songId : null;
    final offline = _offlineFallback || _networkType == NetworkType.offline;

    return Scaffold(
      appBar: AppBar(
        title: Text(_total > 0 ? '$_total songs' : 'Library'),
        actions: [
          if (!_offlineFallback)
            IconButton(
              icon: _fetchingBatchList
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(_batchActive
                      ? Icons.cancel_outlined
                      : Icons.download_for_offline_outlined),
              tooltip: _batchActive
                  ? 'Cancel downloading all'
                  : 'Download all songs',
              onPressed: _fetchingBatchList ? null : _downloadAllTapped,
            ),
          IconButton(
            icon: const Icon(Icons.offline_pin),
            tooltip: 'Downloads',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DownloadsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_reconnecting)
            Container(
              width: double.infinity,
              color: Colors.amber.withValues(alpha: 0.15),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: const Text(
                'Checking connection… downloaded songs are ready',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.amber),
              ),
            )
          else if (_offlineFallback)
            Container(
              width: double.infinity,
              color: Colors.amber.withValues(alpha: 0.15),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                _networkType == NetworkType.offline
                    ? 'Offline — playing downloaded songs'
                    : 'Desktop unreachable — showing downloaded songs only',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.amber),
              ),
            )
          else if (_networkType == NetworkType.offline)
            Container(
              width: double.infinity,
              color: Colors.redAccent.withValues(alpha: 0.15),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: const Text(
                'Offline — showing cached data',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.redAccent),
              ),
            )
          else if (_server != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Connected: ${_server!.label}',
                style: const TextStyle(color: Colors.white24, fontSize: 11),
              ),
            ),
          if (_batchActive)
            Container(
              width: double.infinity,
              color: const Color(0xFFB03A2E).withValues(alpha: 0.12),
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Downloading $_batchDone/$_batchTotal…',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12.5),
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _batchTotal > 0
                                ? _batchDone / _batchTotal
                                : null,
                            minHeight: 4,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _cache.cancelBatch(),
                    child: const Text('Cancel',
                        style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<_PlaySource>(
              segments: const [
                ButtonSegment(
                  value: _PlaySource.phone,
                  icon: Icon(Icons.phone_android),
                  label: Text('This phone'),
                ),
                ButtonSegment(
                  value: _PlaySource.pc,
                  icon: Icon(Icons.desktop_windows),
                  label: Text('PC speakers'),
                ),
              ],
              selected: {_source},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                if (offline && s.first == _PlaySource.pc) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'PC speakers need a connection to the desktop',
                      ),
                    ),
                  );
                  return;
                }
                _setSource(s.first);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: _offlineFallback
                    ? 'Search downloaded songs…'
                    : 'Search songs, artists…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
            ),
          ),
          if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notif) {
                  if (_hasMore &&
                      !_loading &&
                      notif.metrics.pixels >
                          notif.metrics.maxScrollExtent - 300) {
                    _loadSongs();
                  }
                  return false;
                },
                child: ListView.builder(
                  itemCount: _songs.length + (_loading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _songs.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final song = _songs[index];
                    final active = _source == _PlaySource.phone
                        ? index == _currentIndex
                        : song.id == activeSongId;
                    return SongTile(
                      song: song,
                      active: active,
                      onTap: () => _onSongTap(index),
                      cacheState: _cacheStateFor(song.id),
                      downloadProgress: _downloadProgress[song.id],
                      onCacheTap: () => _onCacheIconTap(song),
                    );
                  },
                ),
              ),
            ),
          if (_source == _PlaySource.pc && !(_nowPlaying?.attached ?? false))
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Text(
                'Open the Music Player page in the desktop app first — '
                'that\'s what actually drives the PC\'s speakers.',
                style: const TextStyle(color: Colors.white38, fontSize: 12.5),
                textAlign: TextAlign.center,
              ),
            ),
          if (_source == _PlaySource.phone &&
              _currentIndex >= 0 &&
              _currentIndex < _songs.length)
            MiniPlayer(
              player: _player,
              song: _songs[_currentIndex],
              onPrev: _playPrev,
              onNext: _playNext,
              hasPrev: _currentIndex > 0,
              hasNext: _currentIndex + 1 < _songs.length,
            ),
          if (_source == _PlaySource.pc && (_nowPlaying?.attached ?? false))
            PcMiniPlayer(
              title: _nowPlaying!.title,
              artist: _nowPlaying!.artist,
              isPlaying: _nowPlaying!.isPlaying,
              position: _nowPlaying!.position,
              duration: _nowPlaying!.duration,
              hasPrev: _nowPlaying!.hasPrev,
              hasNext: _nowPlaying!.hasNext,
              onPlayPause: () => _sendControl(
                  _nowPlaying!.isPlaying ? 'pause' : 'play'),
              onPrev: () => _sendControl('prev'),
              onNext: () => _sendControl('next'),
              onSeek: (v) => _sendControl('seek', value: v),
            ),
        ],
      ),
    );
  }
}
