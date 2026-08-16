import 'package:flutter/material.dart';
import '../models/song.dart';

String formatDuration(int seconds) {
  if (seconds <= 0) return '';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

enum SongCacheState { none, downloading, cached }

class SongTile extends StatelessWidget {
  final Song song;
  final bool active;
  final VoidCallback onTap;

  /// Whether/how this song is present in the explicit offline cache.
  /// Omit [onCacheTap] entirely to hide the icon (e.g. in a context
  /// where downloading doesn't make sense).
  final SongCacheState cacheState;
  // 0..1 while downloading with a known size, negative for indeterminate.
  final double? downloadProgress;
  final VoidCallback? onCacheTap;

  const SongTile({
    super.key,
    required this.song,
    required this.active,
    required this.onTap,
    this.cacheState = SongCacheState.none,
    this.downloadProgress,
    this.onCacheTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      tileColor: active ? Colors.white.withOpacity(0.06) : null,
      leading: Icon(
        active ? Icons.graphic_eq : Icons.music_note,
        color: active ? const Color(0xFF4EA1FF) : Colors.white38,
      ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: active ? const Color(0xFF4EA1FF) : Colors.white,
          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        song.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white54),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatDuration(song.duration),
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          if (onCacheTap != null) ...[
            const SizedBox(width: 4),
            _CacheIcon(
              state: cacheState,
              progress: downloadProgress,
              onTap: onCacheTap!,
            ),
          ],
        ],
      ),
    );
  }
}

class _CacheIcon extends StatelessWidget {
  final SongCacheState state;
  final double? progress;
  final VoidCallback onTap;

  const _CacheIcon({
    required this.state,
    required this.progress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case SongCacheState.cached:
        return IconButton(
          icon: const Icon(Icons.offline_pin, color: Color(0xFF4EA1FF)),
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          tooltip: 'Downloaded — tap to remove',
          onPressed: onTap,
        );
      case SongCacheState.downloading:
        final p = progress;
        return SizedBox(
          width: 36,
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: (p != null && p >= 0) ? p : null,
                  color: const Color(0xFF4EA1FF),
                  backgroundColor: Colors.white12,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 12),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                color: Colors.white38,
                tooltip: 'Cancel download',
                onPressed: onTap,
              ),
            ],
          ),
        );
      case SongCacheState.none:
        return IconButton(
          icon: const Icon(Icons.download_outlined, color: Colors.white38),
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          tooltip: 'Download for offline',
          onPressed: onTap,
        );
    }
  }
}
