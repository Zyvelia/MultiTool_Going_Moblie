import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/now_playing.dart';
import '../models/server_profile.dart';
import '../models/song.dart';
import '../services/api_service.dart';
import '../services/connectivity_service.dart';
import '../services/offline_cache_service.dart';
import '../services/settings_service.dart';
import '../services/user_facing_error.dart';
import '../theme/app_colors.dart';
import '../widgets/mini_player.dart';
import '../widgets/pc_mini_player.dart';
import '../widgets/song_tile.dart';
import 'downloads_screen.dart';

enum _PlaySource { phone, pc }

enum _BrowseTab { songs, artists }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  final _settings = SettingsService();
  ApiService? _api;
  ResolvedServer? _server;
  AudioPlayer? _audio;
  StreamSubscription<int?>? _indexSub;
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

  _PlaySource _source = _PlaySource.phone;
  Timer? _pollTimer;
  NowPlaying? _nowPlaying;
  bool _sendingControl = false;

  int _midStreamRetries = 0;

  final _cache = OfflineCacheService.instance;
  StreamSubscription<CacheEvent>? _cacheSub;
  final Map<int, double> _downloadProgress = {};
  bool _batchActive = false;
  int _batchDone = 0;
  int _batchTotal = 0;
  bool _fetchingBatchList = false;
  bool _offlineFallback = false;

  ConcatenatingAudioSource? _playlist;
  int _playGen = 0;
  Directory? _remoteCacheDir;

  // Browse tab state
  _BrowseTab _browseTab = _BrowseTab.songs;
  // Artist expand state — key is artist name
  final Set<String> _expandedArtists = {};
  // Artist list built from the cached songs (always available offline)
  Map<String, List<Song>> _artistMap = {};

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) {
          setState(() {
            _browseTab =
                _tabController.index == 0 ? _BrowseTab.songs : _BrowseTab.artists;
          });
          // When switching to Artists tab, always build from cache
          if (_browseTab == _BrowseTab.artists) _rebuildArtistMap();
        }
      });
    _init();
    _initConnectivity();
    _cacheSub = _cache.events.listen(_onCacheEvent);
  }

  AudioPlayer get _player => _audio!;
  bool get _hasPlayer => _audio != null;

  Future<void> _ensurePlayer() async {
    if (_audio != null) return;
    final player = AudioPlayer();
    _audio = player;
    _indexSub = player.currentIndexStream.listen((index) {
      if (mounted && index != null && index != _currentIndex) {
        setState(() => _currentIndex = index);
      }
    });
    player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        final index = player.currentIndex;
        if (index == null || index < 0 || index >= _songs.length) return;
        if (_cache.isCached(_songs[index].id)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(explainError(e, doing: 'play this song'))),
            );
          }
          return;
        }
        if (_midStreamRetries >= 2) {
          _midStreamRetries = 0;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(explainError(e, doing: 'keep playing'))),
            );
          }
          return;
        }
        _midStreamRetries++;
        final resumeAt = player.position;
        Future.delayed(Duration(milliseconds: 500 * _midStreamRetries), () async {
          if (!mounted) return;
          await _recoverTrack(index, resumeAt);
        });
      },
    );
  }

  Future<void> _recoverTrack(int index, Duration resumeAt) async {
    if (index < 0 || index >= _songs.length) return;
    final song = _songs[index];
    if (_cache.isCached(song.id)) {
      try {
        await _player.setAudioSource(
          _sourceFor(song),
          initialPosition: resumeAt,
        );
        await _player.play();
        _midStreamRetries = 0;
        _playlist = null;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(explainError(e, doing: 'play this song'))),
          );
        }
      }
      return;
    }
    try {
      await _player.setAudioSource(
        _sourceFor(song),
        initialPosition: resumeAt,
      );
      await _player.play();
      _midStreamRetries = 0;
      _playlist = null;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(explainError(e, doing: 'play this song'))),
        );
      }
    }
  }

  Future<void> _init() async {
    await _cache.ensureReady();
    unawaited(_ensureRemoteCacheDir());

    if (_cache.count > 0) {
      _paintCachedLibrary();
      _rebuildArtistMap();
      if (mounted) setState(() => _reconnecting = true);
      await Future<void>.delayed(Duration.zero);
    }

    final net = await ConnectivityService.instance.current();
    if (mounted) setState(() => _networkType = net);

    if (net == NetworkType.offline) {
      unawaited(_resolveServer(skipProbe: true));
      _paintCachedLibrary();
      return;
    }

    await _connectAndLoadLive();
  }

  Future<void> _ensureRemoteCacheDir() async {
    if (_remoteCacheDir != null) return;
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/just_audio_cache/remote');
    await dir.create(recursive: true);
    _remoteCacheDir = dir;
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

  void _paintSongs(
    List<Song> songs, {
    required bool reset,
    int? total,
    bool hasMore = false,
    bool offlineFallback = false,
  }) {
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
    _rebuildArtistMap();
  }

  void _paintCachedLibrary() {
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
    _paintSongs(list, reset: true, offlineFallback: true);
  }

  /// Rebuilds the artist → songs map from the current _songs list.
  /// Called whenever _songs changes, or when switching to Artists tab.
  void _rebuildArtistMap() {
    final map = <String, List<Song>>{};
    final source =
        _offlineFallback ? _cache.downloadedSongs : _songs;
    for (final song in source) {
      final artist = song.artist.isNotEmpty ? song.artist : 'Unknown Artist';
      (map[artist] ??= []).add(song);
    }
    // Sort artists alphabetically
    final sorted = Map.fromEntries(
      map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    if (mounted) setState(() => _artistMap = sorted);
  }

  /// Filters the artist map by the current search query.
  Map<String, List<Song>> get _filteredArtistMap {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _artistMap;
    final result = <String, List<Song>>{};
    for (final entry in _artistMap.entries) {
      if (entry.key.toLowerCase().contains(q)) {
        // Whole artist matches — show all songs
        result[entry.key] = entry.value;
      } else {
        // Check individual songs
        final matching = entry.value
            .where((s) =>
                s.title.toLowerCase().contains(q) ||
                s.album.toLowerCase().contains(q))
            .toList();
        if (matching.isNotEmpty) result[entry.key] = matching;
      }
    }
    return result;
  }

  Future<void> _applySongList(
    List<Song> songs, {
    required bool reset,
    int? total,
    bool hasMore = false,
    bool offlineFallback = false,
  }) async {
    _paintSongs(
      songs,
      reset: reset,
      total: total,
      hasMore: hasMore,
      offlineFallback: offlineFallback,
    );
    if (reset) _playlist = null;
  }

  Future<void> _showCachedLibrary() async {
    await _cache.ensureReady();
    _paintCachedLibrary();
    _playlist = null;
  }

  ConcatenatingAudioSource _playlistFrom(List<Song> songs) {
    return ConcatenatingAudioSource(
      useLazyPreparation: true,
      children: [for (final s in songs) _sourceFor(s)],
    );
  }

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
      if (!wasOffline) return;

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
    _tabController.dispose();
    _debounce?.cancel();
    _pollTimer?.cancel();
    _connectivitySub?.cancel();
    _cacheSub?.cancel();
    _indexSub?.cancel();
    _audio?.dispose();
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
            SnackBar(content: Text(explainError(evt.error ?? 'download failed', doing: 'download that song'))),
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
    // Keep artist map fresh when cache changes
    if (evt.type == CacheEventType.completed ||
        evt.type == CacheEventType.removed ||
        evt.type == CacheEventType.batchFinished ||
        evt.type == CacheEventType.cleared) {
      _rebuildArtistMap();
    }
  }

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
          SnackBar(content: Text(explainError(e, doing: 'load the full song list'))),
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
            _error = explainError(e, doing: 'load the music library');
            _loading = false;
            _reconnecting = false;
          });
        }
      } else if (mounted) {
        setState(() {
          _error = explainError(e, doing: 'load the music library');
          _loading = false;
        });
      }
    } finally {
      _fetching = false;
    }
  }

  AudioSource _sourceFor(Song song) {
    final tag = MediaItem(
      id: song.id.toString(),
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: song.duration > 0 ? Duration(seconds: song.duration) : null,
    );

    final local = _cache.isCached(song.id) ? _cache.localFile(song.id) : null;
    if (local != null && local.existsSync()) {
      return AudioSource.file(local.path, tag: tag);
    }
    if (_api == null) {
      return AudioSource.file(local?.path ?? '', tag: tag);
    }
    final uri = Uri.parse(_api!.streamUrl(song.id));
    final dir = _remoteCacheDir;
    if (dir != null) {
      return LockCachingAudioSource(
        uri,
        cacheFile: File('${dir.path}/${song.id}'),
        tag: tag,
      );
    }
    return LockCachingAudioSource(uri, tag: tag);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _query = value);
      if (_browseTab == _BrowseTab.artists) {
        // Artist tab always filters locally — no server hit needed
        _rebuildArtistMap();
        return;
      }
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
      if (_hasPlayer) _player.pause();
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
    } catch (_) {}
  }

  Future<void> _sendControl(String action, {int? songId, double? value}) async {
    if (_api == null || _sendingControl) return;
    _sendingControl = true;
    try {
      await _api!.control(action, songId: songId, value: value);
      await _pollNowPlaying();
    } on ControlException catch (e) {
      await _pollNowPlaying();
      if (mounted && !e.transient) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(explainError(e, doing: 'control the PC player'))),
        );
      }
    } catch (e) {
      await _pollNowPlaying();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(explainError(e, doing: 'control the PC player'))),
        );
      }
    } finally {
      _sendingControl = false;
    }
  }

  Future<void> _playIndex(int index) async {
    if (index < 0 || index >= _songs.length) return;
    final gen = ++_playGen;
    final song = _songs[index];
    final local = _cache.isCached(song.id);

    await _ensurePlayer();
    await _ensureRemoteCacheDir();
    if (gen != _playGen || !mounted) return;

    setState(() => _currentIndex = index);

    Future<void> playAt(int i) async {
      final source = _playlistFrom(List<Song>.from(_songs));
      await _player.setAudioSource(
        source,
        initialIndex: i,
        initialPosition: Duration.zero,
      );
      if (gen != _playGen) return;
      _playlist = source;
      await _player.play();
      _midStreamRetries = 0;
    }

    Future<void> playFile() async {
      await _player.setAudioSource(_sourceFor(song));
      if (gen != _playGen) return;
      _playlist = null;
      await _player.play();
      _midStreamRetries = 0;
    }

    try {
      await playAt(index);
    } catch (e) {
      if (local) {
        try {
          await playFile();
        } catch (e2) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(explainError(e2, doing: 'play this song'))),
            );
          }
        }
        return;
      }
      if (_api == null) return;
      for (var attempt = 1; attempt <= 3; attempt++) {
        if (gen != _playGen) return;
        try {
          await playAt(index);
          return;
        } catch (err) {
          if (attempt == 3) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(explainError(err, doing: 'play this song'))),
              );
            }
            return;
          }
          await Future.delayed(Duration(milliseconds: 400 * attempt));
        }
      }
    }
  }

  /// Play a song directly from the Artists view — loads it as a single
  /// track (no cross-artist playlist context).
  Future<void> _playArtistSong(Song song) async {
    // Find the song in _songs list to get a proper index if it's there
    final idx = _songs.indexWhere((s) => s.id == song.id);
    if (idx >= 0) {
      _playIndex(idx);
      return;
    }
    // Song only exists in cache (offline fallback with no server list)
    // Load it as a single track
    final gen = ++_playGen;
    await _ensurePlayer();
    await _ensureRemoteCacheDir();
    if (gen != _playGen || !mounted) return;

    // Inject it into _songs temporarily so mini player has context
    final tempList = [song];
    setState(() {
      _songs
        ..clear()
        ..addAll(tempList);
      _currentIndex = 0;
      _offset = 1;
      _total = 1;
      _hasMore = false;
    });
    _playlist = null;

    try {
      await _player.setAudioSource(_sourceFor(song));
      if (gen != _playGen) return;
      await _player.play();
      _midStreamRetries = 0;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(explainError(e, doing: 'play this song'))),
        );
      }
    }
  }

  void _playNext() {
    if (_currentIndex + 1 >= _songs.length) return;
    if (_hasPlayer && _playlist != null && _player.hasNext) {
      _player.seekToNext();
      return;
    }
    _playIndex(_currentIndex + 1);
  }

  void _playPrev() {
    if (_currentIndex <= 0) return;
    if (_hasPlayer && _playlist != null && _player.hasPrevious) {
      _player.seekToPrevious();
      return;
    }
    _playIndex(_currentIndex - 1);
  }

  void _onSongTap(int index) {
    if (_source == _PlaySource.phone || _offlineFallback) {
      _playIndex(index);
    } else {
      _sendControl('play_song', songId: _songs[index].id);
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: Colors.white38,
          tabs: const [
            Tab(icon: Icon(Icons.queue_music), text: 'Songs'),
            Tab(icon: Icon(Icons.person), text: 'Artists'),
          ],
        ),
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
              tooltip: _batchActive ? 'Cancel downloading all' : 'Download all songs',
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
          // ── Status banners ──────────────────────────────────────────────
          if (_reconnecting)
            _StatusBanner(
              message: 'Checking connection… downloaded songs are ready',
              color: Colors.amber,
            )
          else if (_offlineFallback)
            _StatusBanner(
              message: _networkType == NetworkType.offline
                  ? 'Offline — playing downloaded songs'
                  : 'Desktop unreachable — showing downloaded songs only',
              color: Colors.amber,
            )
          else if (_networkType == NetworkType.offline)
            _StatusBanner(
              message: 'Offline — showing cached data',
              color: Colors.redAccent,
            )
          else if (_server != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Connected: ${_server!.label}',
                style: const TextStyle(color: Colors.white24, fontSize: 11),
              ),
            ),

          // ── Batch download progress ──────────────────────────────────────
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
                          style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _batchTotal > 0 ? _batchDone / _batchTotal : null,
                            minHeight: 4,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _cache.cancelBatch(),
                    child: const Text('Cancel', style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            ),

          // ── Play source toggle ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
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
                      content: Text('PC speakers need a connection to the desktop'),
                    ),
                  );
                  return;
                }
                _setSource(s.first);
              },
            ),
          ),

          // ── Search ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: _offlineFallback
                    ? 'Search downloaded songs…'
                    : 'Search songs, artists, albums…',
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              ),
            ),
          ),

          // ── Tab content ──────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSongsTab(activeSongId),
                _buildArtistsTab(),
              ],
            ),
          ),

          // ── PC hint ─────────────────────────────────────────────────────
          if (_source == _PlaySource.pc && !(_nowPlaying?.attached ?? false))
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
              child: Text(
                'Open the Music Player page in the desktop app first — '
                'that\'s what actually drives the PC\'s speakers.',
                style: const TextStyle(color: Colors.white38, fontSize: 12.5),
                textAlign: TextAlign.center,
              ),
            ),

          // ── Mini players ─────────────────────────────────────────────────
          if (_source == _PlaySource.phone &&
              _hasPlayer &&
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
              onPlayPause: () =>
                  _sendControl(_nowPlaying!.isPlaying ? 'pause' : 'play'),
              onPrev: () => _sendControl('prev'),
              onNext: () => _sendControl('next'),
              onSeek: (v) => _sendControl('seek', value: v),
            ),
        ],
      ),
    );
  }

  // ─── Songs tab ────────────────────────────────────────────────────────────

  Widget _buildSongsTab(int? activeSongId) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.redAccent),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notif) {
        if (_hasMore &&
            !_loading &&
            notif.metrics.pixels > notif.metrics.maxScrollExtent - 300) {
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
    );
  }

  // ─── Artists tab ──────────────────────────────────────────────────────────

  Widget _buildArtistsTab() {
    final map = _filteredArtistMap;

    if (map.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_off_outlined, color: Colors.white24, size: 48),
              const SizedBox(height: 12),
              Text(
                _query.isNotEmpty
                    ? 'No artists match "$_query"'
                    : 'No downloaded songs yet.\nDownload songs to browse by artist offline.',
                style: const TextStyle(color: Colors.white38, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: map.length,
      itemBuilder: (context, i) {
        final artist = map.keys.elementAt(i);
        final songs = map[artist]!;
        final isExpanded = _expandedArtists.contains(artist);
        final cachedCount = songs.where((s) => _cache.isCached(s.id)).length;

        return Column(
          children: [
            // Artist header row
            InkWell(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedArtists.remove(artist);
                  } else {
                    _expandedArtists.add(artist);
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isExpanded
                          ? AppColors.accent.withValues(alpha: 0.3)
                          : AppColors.border,
                      width: 0.5,
                    ),
                  ),
                  color: isExpanded
                      ? AppColors.accentMuted
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.wine,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(Icons.person, color: AppColors.accent, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            artist,
                            style: TextStyle(
                              color: isExpanded ? AppColors.accent : Colors.white,
                              fontWeight: isExpanded
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                '${songs.length} song${songs.length == 1 ? '' : 's'}',
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 12),
                              ),
                              if (cachedCount > 0) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.offline_pin,
                                    size: 11, color: AppColors.accent),
                                const SizedBox(width: 2),
                                Text(
                                  '$cachedCount',
                                  style: const TextStyle(
                                      color: AppColors.accent, fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.white24,
                    ),
                  ],
                ),
              ),
            ),

            // Expanded songs
            if (isExpanded)
              ...songs.map((song) {
                final active = _source == _PlaySource.phone &&
                    _songs.isNotEmpty &&
                    _currentIndex >= 0 &&
                    _currentIndex < _songs.length &&
                    _songs[_currentIndex].id == song.id;
                return Container(
                  decoration: const BoxDecoration(
                    color: AppColors.accentMuted,
                    border: Border(
                      bottom: BorderSide(color: AppColors.border, width: 0.5),
                    ),
                  ),
                  child: SongTile(
                    song: song,
                    active: active,
                    onTap: () {
                      if (_source == _PlaySource.pc && !_offlineFallback) {
                        _sendControl('play_song', songId: song.id);
                      } else {
                        _playArtistSong(song);
                      }
                    },
                    cacheState: _cacheStateFor(song.id),
                    downloadProgress: _downloadProgress[song.id],
                    onCacheTap: _api != null || _cache.isCached(song.id)
                        ? () => _onCacheIconTap(song)
                        : null,
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final String message;
  final Color color;

  const _StatusBanner({required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: color),
      ),
    );
  }
}
