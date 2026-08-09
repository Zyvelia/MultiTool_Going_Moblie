import 'package:shared_preferences/shared_preferences.dart';

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
<<<<<<< HEAD
  static const notes = 8448;
=======
>>>>>>> 45c6d9bb297507350a62a30d1707a40d51d0e3e7
}

class SettingsService {
  static const _hostKey = 'tailscale_hostname';
  static const _gamesCodeKey = 'games_access_code';
  static const _soundboardCodeKey = 'soundboard_access_code';
  static const _ytCodeKey = 'yt_access_code';

  Future<String?> getHostname() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_hostKey);
  }

  Future<void> setHostname(String hostname) async {
    final prefs = await SharedPreferences.getInstance();
    // Accept either a bare hostname or a full https://host:port URL
    // pasted in by mistake — strip scheme/port/path down to just the host.
    var h = hostname.trim();
    h = h.replaceFirst(RegExp(r'^https?://'), '');
    h = h.split('/').first;
    h = h.split(':').first;
    await prefs.setString(_hostKey, h);
  }

  Future<String?> getAccessCode(String moduleKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyFor(moduleKey));
  }

  Future<void> setAccessCode(String moduleKey, String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFor(moduleKey), code.trim());
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
      _ => throw ArgumentError('unknown module $moduleKey'),
    };
    return 'https://$host:$port';
  }
}
