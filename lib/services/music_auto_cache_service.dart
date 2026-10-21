import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import 'connectivity_service.dart';
import 'offline_cache_service.dart';
import 'settings_service.dart';
import 'api_service.dart';

/// When on Wi‑Fi (and Wi‑Fi-only downloads allow it), cache all songs
/// for artists the user pinned for auto-download.
class MusicAutoCacheService {
  MusicAutoCacheService._();
  static final instance = MusicAutoCacheService._();

  static const _prefsKey = 'music_auto_cache_artists_v1';

  Future<Set<String>> getArtistNames() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw) as List;
      return list.whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> setArtistNames(Set<String> names) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(names.toList()..sort()));
  }

  Future<void> toggleArtist(String artist, bool enabled) async {
    final set = await getArtistNames();
    if (enabled) {
      set.add(artist);
    } else {
      set.remove(artist);
    }
    await setArtistNames(set);
  }

  Future<bool> isArtistEnabled(String artist) async {
    final set = await getArtistNames();
    return set.contains(artist);
  }

  /// Best-effort background caching for pinned artists.
  Future<void> runIfAllowed({
    required List<Song> librarySongs,
    required ApiService api,
  }) async {
    final pinned = await getArtistNames();
    if (pinned.isEmpty) return;

    final settings = SettingsService();
    final wifiOnly = await settings.getMusicWifiOnlyDownloads();
    final net = await ConnectivityService.instance.current();
    if (net == NetworkType.offline) return;
    if (wifiOnly && net != NetworkType.wifi && net != NetworkType.ethernet) {
      return;
    }

    final cache = OfflineCacheService.instance;
    await cache.ensureReady();
    final toFetch = <Song>[];
    for (final song in librarySongs) {
      final artist = song.artist.trim().isEmpty ? 'Unknown Artist' : song.artist.trim();
      if (!pinned.contains(artist)) continue;
      if (cache.isCached(song.id) || cache.isDownloading(song.id)) continue;
      toFetch.add(song);
    }
    for (final song in toFetch) {
      await cache.download(song, api);
    }
  }
}
