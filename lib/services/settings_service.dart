import 'dart:async';
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
  static const _musicPreferredServerKey = 'music_preferred_server';
  static const _musicWifiOnlyKey = 'music_wifi_only_downloads';

  // Backed by iOS Keychain / Android EncryptedSharedPreferences instead of
  // shared_preferences. shared_preferences data lives in the app sandbox
  // and gets wiped on uninstall — which meant re-typing the Tailscale
  // hostname after every reinstall (e.g. after a TrollStore icon-cache
  // fix). Keychain entries survive app deletion by default, so this
  // persists across reinstalls.
  static const _storage = FlutterSecureStorage(
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
  ///   timeout; fall back to public if it doesn't answer. The probe is
  ///   deliberately cheap (a single GET with a 2.5s timeout) since this
  ///   runs on every cold connect, not just in the diagnostics screen.
  Future<ResolvedServer?> resolveMusicServer() async {
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
        if (await _quickReachable(private)) {
          return ResolvedServer(private, 'Private (Tailscale)');
        }
        return ResolvedServer(public, 'Public');
    }
  }

  Future<bool> _quickReachable(String baseUrl) async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/status'))
          .timeout(const Duration(milliseconds: 2500));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
