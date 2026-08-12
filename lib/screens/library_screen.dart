import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../models/song.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../widgets/mini_player.dart';
import '../widgets/song_tile.dart';

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
                    return SongTile(
                      song: song,
                      active: index == _currentIndex,
                      onTap: () => _playIndex(index),
                    );
                  },
                ),
              ),
            ),
          if (_currentIndex >= 0 && _currentIndex < _songs.length)
            MiniPlayer(
              player: _player,
              song: _songs[_currentIndex],
              onPrev: _playPrev,
              onNext: _playNext,
              hasPrev: _currentIndex > 0,
              hasNext: _currentIndex + 1 < _songs.length,
            ),
        ],
      ),
    );
  }
}
