import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../models/song.dart';
import '../models/now_playing.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../widgets/mini_player.dart';
import '../widgets/pc_mini_player.dart';
import '../widgets/song_tile.dart';

enum PlaybackMode { phone, pc }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _settings = SettingsService();
  ApiService? _api;
  final _player = AudioPlayer();
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

  // --- PC control mode ---
  PlaybackMode _mode = PlaybackMode.phone;
  Timer? _pcPollTimer;
  NowPlaying? _nowPlaying;
  String? _pcError;
  bool _pcSeeking = false; // suppress poll overwrites while dragging

  @override
  void initState() {
    super.initState();
    _init();
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _playNext();
      }
    });
  }

  Future<void> _init() async {
    final base = await _settings.baseUrl('music');
    if (base == null) return;
    setState(() => _api = ApiService(base));
    await _loadSongs(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pcPollTimer?.cancel();
    _player.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // -----------------------------------------------------------
  // Mode switching
  // -----------------------------------------------------------

  Future<void> _setMode(PlaybackMode mode) async {
    if (mode == _mode) return;
    if (mode == PlaybackMode.pc) {
      // Stop local playback before handing off — don't play in two
      // places at once.
      await _player.pause();
      setState(() {
        _mode = mode;
        _pcError = null;
      });
      _startPcPolling();
    } else {
      _pcPollTimer?.cancel();
      setState(() => _mode = mode);
    }
  }

  void _startPcPolling() {
    _pcPollTimer?.cancel();
    _pollNowPlaying(); // immediate first fetch, don't wait a full second
    _pcPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _pollNowPlaying();
    });
  }

  Future<void> _pollNowPlaying() async {
    if (_api == null || _pcSeeking) return;
    try {
      final np = await _api!.fetchNowPlaying();
      if (!mounted) return;
      setState(() {
        _nowPlaying = np;
        _pcError = np.attached
            ? null
            : 'Open the Music Player page in the desktop app first.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _pcError = 'Lost connection: $e');
    }
  }

  // -----------------------------------------------------------
  // Library loading (shared by both modes — PC mode still browses
  // the same list, it just taps a different action to start playback)
  // -----------------------------------------------------------

  Future<void> _loadSongs({bool reset = false}) async {
    if (_api == null || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _offset = 0;
        _songs.clear();
      }
    });
    try {
      final result =
          await _api!.fetchSongs(query: _query, offset: _offset, limit: 100);
      setState(() {
        _songs.addAll(result.songs);
        _offset += result.songs.length;
        _total = result.total;
        _hasMore = result.hasMore;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load library: $e';
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _query = value);
      _loadSongs(reset: true);
    });
  }

  // -----------------------------------------------------------
  // Phone-mode playback
  // -----------------------------------------------------------

  Future<void> _playIndex(int index) async {
    if (_api == null || index < 0 || index >= _songs.length) return;
    setState(() => _currentIndex = index);
    final song = _songs[index];
    try {
      // LockCachingAudioSource streams like a normal URL source on first
      // play, but writes what it downloads to a local cache file as it
      // goes — so replaying the same song (even with a flaky Tailscale
      // connection) reads from disk instead of re-streaming. The
      // MediaItem tag is what shows up on the lock screen / notification
      // via just_audio_background.
      final source = LockCachingAudioSource(
        Uri.parse(_api!.streamUrl(song.id)),
        tag: MediaItem(
          id: song.id.toString(),
          title: song.title,
          artist: song.artist,
          album: song.album,
          duration:
              song.duration > 0 ? Duration(seconds: song.duration) : null,
        ),
      );
      await _player.setAudioSource(source);
      await _player.play();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Playback failed: $e')),
        );
      }
    }
  }

  void _playNext() {
    if (_currentIndex + 1 < _songs.length) _playIndex(_currentIndex + 1);
  }

  void _playPrev() {
    if (_currentIndex > 0) _playIndex(_currentIndex - 1);
  }

  // -----------------------------------------------------------
  // PC-mode playback (all just POSTs /api/control; the next poll
  // tick picks up the resulting state, but each call also returns
  // a fresh snapshot so the UI updates immediately instead of
  // waiting up to a second for the next poll)
  // -----------------------------------------------------------

  Future<void> _pcTap(Song song) async {
    if (_api == null) return;
    try {
      final np = await _api!.pcPlaySong(song.id);
      if (mounted) setState(() => _nowPlaying = np);
    } catch (e) {
      _showPcError(e);
    }
  }

  Future<void> _pcPlayPause() async {
    if (_api == null || _nowPlaying == null) return;
    try {
      final np = _nowPlaying!.isPlaying
          ? await _api!.pcPause()
          : await _api!.pcPlay();
      if (mounted) setState(() => _nowPlaying = np);
    } catch (e) {
      _showPcError(e);
    }
  }

  Future<void> _pcNext() async {
    if (_api == null) return;
    try {
      final np = await _api!.pcNext();
      if (mounted) setState(() => _nowPlaying = np);
    } catch (e) {
      _showPcError(e);
    }
  }

  Future<void> _pcPrev() async {
    if (_api == null) return;
    try {
      final np = await _api!.pcPrev();
      if (mounted) setState(() => _nowPlaying = np);
    } catch (e) {
      _showPcError(e);
    }
  }

  Future<void> _pcSeek(double seconds) async {
    if (_api == null) return;
    try {
      final np = await _api!.pcSeek(seconds);
      if (mounted) setState(() => _nowPlaying = np);
    } catch (e) {
      _showPcError(e);
    } finally {
      _pcSeeking = false;
    }
  }

  void _showPcError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$e')));
  }

  // -----------------------------------------------------------
  // Build
  // -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_api == null) {
      return const Scaffold(
        body: Center(
          child: Text('Set your PC hostname in Settings first.',
              style: TextStyle(color: Colors.white54)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_total > 0 ? '$_total songs' : 'Library'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _ModeSwitch(mode: _mode, onChanged: _setMode),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search songs, artists…',
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
          if (_mode == PlaybackMode.pc && _pcError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                _pcError!,
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
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
                    final active = _mode == PlaybackMode.phone
                        ? index == _currentIndex
                        : (_nowPlaying?.songId == song.id);
                    return SongTile(
                      song: song,
                      active: active,
                      onTap: () => _mode == PlaybackMode.phone
                          ? _playIndex(index)
                          : _pcTap(song),
                    );
                  },
                ),
              ),
            ),
          if (_mode == PlaybackMode.phone &&
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
          if (_mode == PlaybackMode.pc &&
              _nowPlaying != null &&
              _nowPlaying!.attached)
            PcMiniPlayer(
              title: _nowPlaying!.title,
              artist: _nowPlaying!.artist,
              isPlaying: _nowPlaying!.isPlaying,
              position: _nowPlaying!.position,
              duration: _nowPlaying!.duration,
              hasPrev: _nowPlaying!.hasPrev,
              hasNext: _nowPlaying!.hasNext,
              onPlayPause: _pcPlayPause,
              onPrev: _pcPrev,
              onNext: _pcNext,
              onSeek: (v) {
                _pcSeeking = true;
                setState(() => _nowPlaying = NowPlaying(
                      attached: true,
                      songId: _nowPlaying!.songId,
                      title: _nowPlaying!.title,
                      artist: _nowPlaying!.artist,
                      album: _nowPlaying!.album,
                      isPlaying: _nowPlaying!.isPlaying,
                      position: v,
                      duration: _nowPlaying!.duration,
                      hasPrev: _nowPlaying!.hasPrev,
                      hasNext: _nowPlaying!.hasNext,
                    ));
                _pcSeek(v);
              },
            ),
        ],
      ),
    );
  }
}

/// Small "Phone / PC" segmented toggle for the app bar.
class _ModeSwitch extends StatelessWidget {
  final PlaybackMode mode;
  final ValueChanged<PlaybackMode> onChanged;

  const _ModeSwitch({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B2030),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            icon: Icons.phone_iphone,
            selected: mode == PlaybackMode.phone,
            onTap: () => onChanged(PlaybackMode.phone),
          ),
          _segment(
            icon: Icons.desktop_windows,
            selected: mode == PlaybackMode.pc,
            onTap: () => onChanged(PlaybackMode.pc),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4EA1FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          icon,
          size: 18,
          color: selected ? const Color(0xFF0B0D10) : Colors.white54,
        ),
      ),
    );
  }
}
