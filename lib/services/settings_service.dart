import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One PC hostname, four fixed ports — matches APP_HTTPS_PORTS in
/// core/services/tailscale_service.py on the desktop app. You only
/// ever type your Tailscale hostname once; each module's URL is
/// derived from it.
class ModulePorts {
  static const vault = 8443;
  static const music = 8444;
  static const yt = 8445;
  static const games = 8446;
  static const soundboard = 8447;
  static const notes = 8448;
  static const send = 8449;
}

class SettingsService {
  static const _hostKey = 'tailscale_hostname';
  static const _gamesCodeKey = 'games_access_code';
  static const _soundboardCodeKey = 'soundboard_access_code';
  static const _ytCodeKey = 'yt_access_code';

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
      case 'soundboard':
        return _soundboardCodeKey;
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
      'soundboard' => ModulePorts.soundboard,
      'yt' => ModulePorts.yt,
      'notes' => ModulePorts.notes,
      'send' => ModulePorts.send,
      _ => throw ArgumentError('unknown module $moduleKey'),
    };
    return 'https://$host:$port';
  }
}
