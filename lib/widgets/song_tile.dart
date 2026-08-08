import 'package:flutter/material.dart';
import '../models/song.dart';

String formatDuration(int seconds) {
  if (seconds <= 0) return '';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

class SongTile extends StatelessWidget {
  final Song song;
  final bool active;
  final VoidCallback onTap;

  const SongTile({
    super.key,
    required this.song,
    required this.active,
    required this.onTap,
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
      trailing: Text(
        formatDuration(song.duration),
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
    );
  }
}
