import 'package:flutter/material.dart';
import '../models/song.dart';
import '../theme/app_colors.dart';

String formatDuration(int seconds) {
  if (seconds <= 0) return '0:00';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

enum SongCacheState { none, downloading, cached }

String _metadataLine(Song song) {
  final artist = song.artist.trim();
  final album = song.album.trim();
  if (artist.isEmpty && album.isEmpty) return 'Unknown artist';
  if (album.isEmpty) return artist;
  if (artist.isEmpty) return album;
  return '$artist · $album';
}

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 3, 12, 3),
      child: Material(
        color: active ? AppColors.accentMuted : AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: active ? AppColors.accent : AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      onTap: onTap,
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.wine, AppColors.accentMuted]),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(active ? Icons.graphic_eq : Icons.music_note,
          color: active ? AppColors.accentGlow : AppColors.muted),
      ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: active ? AppColors.accent : Colors.white,
          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        _metadataLine(song),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.muted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatDuration(song.duration),
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
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
    ),
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
          icon: const Icon(Icons.offline_pin, color: AppColors.accent),
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
                  value: (p != null && p.isFinite && p >= 0) ? p.clamp(0.0, 1.0) : null,
                  color: AppColors.accent,
                  backgroundColor: Colors.white12,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 12),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                color: AppColors.muted,
                tooltip: 'Cancel download',
                onPressed: onTap,
              ),
            ],
          ),
        );
      case SongCacheState.none:
        return IconButton(
          icon: const Icon(Icons.download_outlined, color: AppColors.muted),
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          tooltip: 'Download for offline',
          onPressed: onTap,
        );
    }
  }
}
