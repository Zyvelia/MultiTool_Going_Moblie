import 'dart:async';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../models/server_profile.dart';

/// One PC hostname, four fixed ports — matches APP_HTTPS_PORTS in
/// core/services/tailscale_service.py on the desktop app. You only
/// ever type your Tailscale hostname once; each module's URL is
/// derived from it.
class ModulePorts {
  static const vault = 8443;
  static const music = 8444;
  static const yt = 8445;
  static const games = 8446;
  static const notes = 8448;
  static const send = 8449;
  static const clipboard = 8451;
  static const messages = 8452;
}

class SettingsService {
  static const _hostKey = 'tailscale_hostname';
  static const _gamesCodeKey = 'games_access_code';
  static const _ytCodeKey = 'yt_access_code';

  // Music is the one module that can also be reached over a public
  // HTTPS API (see server_profile.dart) rather than only Tailscale —
  // everything else stays Tailscale-only, matching the fixed
  // ModulePorts scheme above.
  static const _musicPublicUrlKey = 'music_public_base_url';
  static const _brickBreakerLbUrlKey = 'brick_breaker_leaderboard_url';
  static const _musicPreferredServerKey = 'music_preferred_server';
  static const _musicWifiOnlyKey = 'music_wifi_only_downloads';

  /// Default global leaderboard (Cloudflare Worker) — same board as the web game.
  static const brickBreakerLeaderboardDefaultUrl =
      'https://brick-breaker-leaderboard.itszyvelia.workers.dev';

  // Backed by iOS Keychain / Android EncryptedSharedPreferences instead of
  // shared_preferences. shared_preferences data lives in the app sandbox
  // and gets wiped on uninstall — which meant re-typing the Tailscale
  // hostname after every reinstall (e.g. after a TrollStore icon-cache
  // fix). Keychain entries survive app deletion by default, so this
  // persists across reinstalls.
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      // v9 → v11 cipher migration; safe if the app was never installed before.
      migrateWithBackup: true,
    ),
    iOptions: IOSOptions(
      // Keep the item even if the app is deleted; only wiped by an
      // explicit reset or a full device erase.
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  Future<String?> getHostname() async {
    return _storage.read(key: _hostKey);
  }

  Future<void> setHostname(String hostname) async {
    // Accept either a bare hostname or a full https://host:port URL
    // pasted in by mistake — strip scheme/port/path down to just the host.
    var h = hostname.trim();
    h = h.replaceFirst(RegExp(r'^https?://'), '');
    h = h.split('/').first;
    h = h.split(':').first;
    await _storage.write(key: _hostKey, value: h);
  }

  static const _deviceIdKey = 'device_id';

  /// Stable per-install identity used as Message.senderId — generated
  /// once and kept in the same Keychain/EncryptedSharedPreferences store
  /// as the hostname, so it survives reinstalls the same way.
  Future<String> getOrCreateDeviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _randomHex(16);
    await _storage.write(key: _deviceIdKey, value: id);
    return id;
  }

  String _randomHex(int length) {
    final rand = Random.secure();
    return List.generate(length, (_) => rand.nextInt(16).toRadixString(16))
        .join();
  }

  Future<String?> getAccessCode(String moduleKey) async {
    return _storage.read(key: _keyFor(moduleKey));
  }

  Future<void> setAccessCode(String moduleKey, String code) async {
    await _storage.write(key: _keyFor(moduleKey), value: code.trim());
  }

  /// Clears all saved settings (hostname + access codes). Wire this up to
  /// a "Reset" button in Settings if you want an explicit way to forget
  /// everything without deleting the app.
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  String _keyFor(String moduleKey) {
    switch (moduleKey) {
      case 'games':
        return _gamesCodeKey;
      case 'yt':
        return _ytCodeKey;
      default:
        return '${moduleKey}_access_code';
    }
  }

  Future<String?> baseUrl(String moduleKey) async {
    final host = await getHostname();
    if (host == null || host.isEmpty) return null;
    final port = switch (moduleKey) {
      'vault' => ModulePorts.vault,
      'music' => ModulePorts.music,
      'games' => ModulePorts.games,
      'yt' => ModulePorts.yt,
      'notes' => ModulePorts.notes,
      'send' => ModulePorts.send,
      'clipboard' => ModulePorts.clipboard,
      'messages' => ModulePorts.messages,
      _ => throw ArgumentError('unknown module $moduleKey'),
    };
    return 'https://$host:$port';
  }

  // ---- Music: public server profile + preference -----------------------

  /// Full base URL for the public music API, e.g.
  /// `https://music.example.com/api`. Stored as entered (minus a
  /// trailing slash) since — unlike the Tailscale profile — there's no
  /// fixed port to derive; the user's public deployment decides its own
  /// port/path.
  Future<String?> getMusicPublicUrl() => _storage.read(key: _musicPublicUrlKey);

  Future<void> setMusicPublicUrl(String url) async {
    var u = url.trim();
    if (u.isEmpty) {
      await _storage.delete(key: _musicPublicUrlKey);
      return;
    }
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    u = u.replaceFirst(RegExp(r'/+$'), '');
    await _storage.write(key: _musicPublicUrlKey, value: u);
  }

  /// Optional public leaderboard API (Cloudflare Worker).
  /// Falls back to [brickBreakerLeaderboardDefaultUrl] when unset.
  Future<String?> getBrickBreakerLeaderboardUrl() async {
    final stored = await _storage.read(key: _brickBreakerLbUrlKey);
    if (stored != null && stored.isNotEmpty) return stored;
    return brickBreakerLeaderboardDefaultUrl;
  }

  Future<void> setBrickBreakerLeaderboardUrl(String url) async {
    var u = url.trim();
    if (u.isEmpty) {
      await _storage.delete(key: _brickBreakerLbUrlKey);
      return;
    }
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    u = u.replaceFirst(RegExp(r'/+$'), '');
    await _storage.write(key: _brickBreakerLbUrlKey, value: u);
  }

  static const _brickBreakerLbSourceKey = 'brick_breaker_leaderboard_source';

  /// `pc` (Tailscale :8450) or `public` (Cloudflare Worker URL).
  /// New installs default to `public`.
  Future<String> getBrickBreakerLeaderboardSourceKey() async {
    final v = await _storage.read(key: _brickBreakerLbSourceKey);
    if (v == null) return 'public';
    return v == 'public' ? 'public' : 'pc';
  }

  Future<void> setBrickBreakerLeaderboardSourceKey(String source) async {
    await _storage.write(
      key: _brickBreakerLbSourceKey,
      value: source == 'public' ? 'public' : 'pc',
    );
  }

  /// Private (Tailscale) base URL for music specifically, using the
  /// fixed music port — same derivation as [baseUrl], exposed directly
  /// since server resolution needs both profiles at once.
  Future<String?> getMusicPrivateUrl() async {
    final host = await getHostname();
    if (host == null || host.isEmpty) return null;
    return 'https://$host:${ModulePorts.music}';
  }

  Future<PreferredServer> getMusicPreferredServer() async {
    return PreferredServerJson.fromStorageString(
      await _storage.read(key: _musicPreferredServerKey),
    );
  }

  Future<void> setMusicPreferredServer(PreferredServer server) async {
    await _storage.write(
      key: _musicPreferredServerKey,
      value: server.toStorageString(),
    );
  }

  Future<bool> getMusicWifiOnlyDownloads() async {
    final v = await _storage.read(key: _musicWifiOnlyKey);
    return v != 'false'; // default true — don't burn cellular data by default
  }

  Future<void> setMusicWifiOnlyDownloads(bool value) async {
    await _storage.write(key: _musicWifiOnlyKey, value: value.toString());
  }

  /// Resolves which music server to actually talk to right now.
  ///
  /// - Only one profile configured → that one, no probing.
  /// - [PreferredServer.private] / [.public] → that one specifically,
  ///   even if unreachable (caller's request will just fail and surface
  ///   a real error — this isn't the place to silently switch servers
  ///   out from under an explicit user choice).
  /// - [PreferredServer.auto] → probe the private address with a short
  ///   timeout; fall back to public if it doesn't answer.
  /// - [skipProbe] skips the private-server ping and returns the private
  ///   URL immediately — used when the OS already reports offline so we
  ///   don't burn seconds waiting for a Tailscale hostname that can't
  ///   resolve.
  Future<ResolvedServer?> resolveMusicServer({
    Duration probeTimeout = const Duration(milliseconds: 800),
    bool skipProbe = false,
  }) async {
    final private = await getMusicPrivateUrl();
    final public = await getMusicPublicUrl();
    final preferred = await getMusicPreferredServer();

    if (private == null && public == null) return null;
    if (private == null) return ResolvedServer(public!, 'Public');
    if (public == null) return ResolvedServer(private, 'Private (Tailscale)');

    switch (preferred) {
      case PreferredServer.private:
        return ResolvedServer(private, 'Private (Tailscale)');
      case PreferredServer.public:
        return ResolvedServer(public, 'Public');
      case PreferredServer.auto:
        if (skipProbe) {
          return ResolvedServer(private, 'Private (Tailscale)');
        }
        if (await _quickReachable(private, probeTimeout)) {
          return ResolvedServer(private, 'Private (Tailscale)');
        }
        return ResolvedServer(public, 'Public');
    }
  }

  Future<bool> _quickReachable(String baseUrl, Duration timeout) async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/status'))
          .timeout(timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
