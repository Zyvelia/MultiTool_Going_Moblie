import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../models/song.dart';
import '../models/now_playing.dart';
import '../models/server_profile.dart';
import '../services/api_service.dart';
import '../services/connectivity_service.dart';
import '../services/offline_cache_service.dart';
import '../services/settings_service.dart';
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
        if (index == null) return;
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
    try {
      await _playlist.removeAt(index);
      await _playlist.insert(index, _sourceFor(_songs[index]));
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
    // Needed before the first _sourceFor call so cached-vs-stream source
    // selection (and offline fallback below) sees real data, not an
    // empty pre-load manifest.
    await _cache.ensureReady();
    final server = await _settings.resolveMusicServer();
    if (server == null) return;
    setState(() {
      _server = server;
      _api = ApiService(server.baseUrl);
    });
    if (!_playlistAttached) {
      await _player.setAudioSource(_playlist);
      _playlistAttached = true;
    }
    await _loadSongs(reset: true);
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
      if (type == NetworkType.offline) return;
      if (!wasOffline) return; // only act on offline -> back-online edges

      setState(() => _reconnecting = true);
      final server = await _settings.resolveMusicServer();
      if (!mounted) return;
      if (server != null && server.baseUrl != _server?.baseUrl) {
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
      }
    });
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
    if (_api == null || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _offset = 0;
        _songs.clear();
        _offlineFallback = false;
      }
    });
    if (reset) await _playlist.clear();
    try {
      final result =
          await _api!.fetchSongs(query: _query, offset: _offset, limit: 100);
      await _playlist.addAll(result.songs.map(_sourceFor).toList());
      setState(() {
        _songs.addAll(result.songs);
        _offset += result.songs.length;
        _total = result.total;
        _hasMore = result.hasMore;
        _loading = false;
        _offlineFallback = false;
      });
    } catch (e) {
      // Desktop unreachable with nothing loaded yet (e.g. cold app start
      // while offline) — fall back to whatever's been explicitly
      // downloaded so the library tab isn't just a dead error screen.
      // Only on a fresh load: mid-pagination failures should surface as
      // a real error instead of silently truncating the visible list.
      final downloaded = reset ? _cache.downloadedSongs : const <Song>[];
      if (reset && downloaded.isNotEmpty) {
        await _playlist.addAll(downloaded.map(_sourceFor).toList());
        setState(() {
          _songs.addAll(downloaded);
          _total = downloaded.length;
          _hasMore = false;
          _loading = false;
          _offlineFallback = true;
        });
      } else {
        setState(() {
          _error = 'Could not load library: $e';
          _loading = false;
        });
      }
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
      return AudioSource.uri(Uri.file(local.path), tag: tag);
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
      _loadSongs(reset: true);
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
    if (_api == null || index < 0 || index >= _songs.length) return;

    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await _player.seek(Duration.zero, index: index);
        await _player.play();
        _midStreamRetries = 0;
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
    if (_source == _PlaySource.phone) {
      _playIndex(index);
    } else {
      _sendControl('play_song', songId: _songs[index].id);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_api == null) {
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

    return Scaffold(
      appBar: AppBar(
        title: Text(_total > 0 ? '$_total songs' : 'Library'),
        actions: [
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
          if (_offlineFallback)
            Container(
              width: double.infinity,
              color: Colors.amber.withValues(alpha: 0.15),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: const Text(
                'Desktop unreachable — showing downloaded songs only',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.amber),
              ),
            )
          else if (_networkType == NetworkType.offline || _reconnecting)
            Container(
              width: double.infinity,
              color: _networkType == NetworkType.offline
                  ? Colors.redAccent.withValues(alpha: 0.15)
                  : Colors.amber.withValues(alpha: 0.15),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                _networkType == NetworkType.offline
                    ? 'Offline — showing cached data'
                    : 'Reconnecting…',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: _networkType == NetworkType.offline
                      ? Colors.redAccent
                      : Colors.amber,
                ),
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
              onSelectionChanged: (s) => _setSource(s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              enabled: !_offlineFallback,
              decoration: InputDecoration(
                hintText: _offlineFallback
                    ? 'Search unavailable offline'
                    : 'Search songs, artists…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: const Color(0xFF1B2030),
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
