import 'dart:async';
import 'package:flutter/material.dart';
import '../models/song.dart';
import '../theme/app_colors.dart';
import '../services/offline_cache_service.dart';
import '../widgets/song_tile.dart';

/// Explicit offline cache management: what's downloaded, how much space
/// it's using, and per-song / all-at-once removal. Pushed from the
/// Library tab's app bar rather than living in the bottom nav — this is
/// a management view, not something you visit every session.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final _cache = OfflineCacheService.instance;
  StreamSubscription<CacheEvent>? _sub;
  List<Song> _songs = [];

  @override
  void initState() {
    super.initState();
    _refresh();
    _sub = _cache.events.listen((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _refresh() {
    setState(() => _songs = _cache.downloadedSongs);
  }

  Future<void> _removeOne(Song song) async {
    await _cache.remove(song.id);
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Clear all downloads?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'This removes all ${_songs.length} downloaded songs '
          '(${formatBytes(_cache.totalBytes)}) from this device. '
          'They stay in your library on the PC.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear all',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _cache.clearAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          if (_songs.isNotEmpty)
            TextButton(
              onPressed: _confirmClearAll,
              child: const Text('Clear all',
                  style: TextStyle(color: Colors.redAccent)),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_songs.length} song${_songs.length == 1 ? '' : 's'} '
                  'downloaded',
                  style: const TextStyle(color: Colors.white70),
                ),
                Text(
                  formatBytes(_cache.totalBytes),
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12.5),
                ),
              ],
            ),
          ),
          Expanded(
            child: _songs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No downloads yet. Tap the ${String.fromCharCode(0x2b07)} '
                        'next to a song in your library to save it for '
                        'offline listening.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white38),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _songs.length,
                    itemBuilder: (context, index) {
                      final song = _songs[index];
                      return SongTile(
                        song: song,
                        active: false,
                        onTap: () {},
                        cacheState: SongCacheState.cached,
                        onCacheTap: () => _removeOne(song),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
