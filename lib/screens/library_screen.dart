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

enum _PlaySource { phone, pc }

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

  // "Phone" streams audio into this screen's own AudioPlayer and plays
  // locally. "PC" instead remote-controls the desktop app's own player
  // (audio comes out of the PC's speakers) via polling /api/now-playing
  // and posting to /api/control.
  _PlaySource _source = _PlaySource.phone;
  Timer? _pollTimer;
  NowPlaying? _nowPlaying;
  bool _sendingControl = false;

  int _midStreamRetries = 0;

  @override
  void initState() {
    super.initState();
    _init();
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        // Calling setAudioSource() synchronously from inside this
        // listener — while ExoPlayer is still finishing its own
        // transition into the "completed" state — is what causes
        // Android's media3 error 1004 (ERROR_CODE_FAILED_RUNTIME_CHECK).
        // Deferring to the next microtask lets that transition settle
        // first.
        Future.microtask(_playNext);
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
        if (_currentIndex < 0) return;
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
          if (!mounted || _currentIndex < 0) return;
          await _playIndex(_currentIndex, resumeAt: resumeAt);
        });
      },
    );
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
    _pollTimer?.cancel();
    _player.dispose();
    _searchController.dispose();
    super.dispose();
  }

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

  Future<void> _playIndex(int index, {Duration? resumeAt}) async {
    if (_api == null || index < 0 || index >= _songs.length) return;
    setState(() => _currentIndex = index);
    final song = _songs[index];

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
        duration: song.duration > 0 ? Duration(seconds: song.duration) : null,
      ),
    );

    // A brief Tailscale connection hiccup right as one track ends and the
    // next one's stream request goes out shows up as iOS's
    // NSURLErrorCannotConnectToHost (-1004) or an equivalent transient
    // error on Android — not a real failure, just bad timing. Retry a
    // couple of times before treating it as one.
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await _player.setAudioSource(source);
        if (resumeAt != null && resumeAt > Duration.zero) {
          await _player.seek(resumeAt);
        }
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
    if (_currentIndex + 1 < _songs.length) _playIndex(_currentIndex + 1);
  }

  void _playPrev() {
    if (_currentIndex > 0) _playIndex(_currentIndex - 1);
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
          child: Text('Set your PC hostname in Settings first.',
              style: TextStyle(color: Colors.white54)),
        ),
      );
    }

    final activeSongId =
        _source == _PlaySource.pc ? _nowPlaying?.songId : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_total > 0 ? '$_total songs' : 'Library'),
      ),
      body: Column(
        children: [
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
