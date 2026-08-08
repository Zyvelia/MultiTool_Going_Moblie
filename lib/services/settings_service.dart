import 'package:shared_preferences/shared_preferences.dart';

/// Persists the base URL of the music web server, e.g.
/// https://my-pc.tailxxxx.ts.net:8444
///
/// This matches the port your desktop app's Music Player > Settings tab
/// shows when "Remote access" is on (default 8444, or whatever you set
/// as the local port there).
class SettingsService {
  static const _key = 'server_base_url';

  Future<String?> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  Future<void> setServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    // Strip a trailing slash so we can safely do "$base/api/..." everywhere.
    final trimmed = url.trim().replaceAll(RegExp(r'/+$'), '');
    await prefs.setString(_key, trimmed);
  }
}
