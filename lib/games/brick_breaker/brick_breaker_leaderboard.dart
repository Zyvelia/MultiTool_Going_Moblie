import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/settings_service.dart';
import 'brick_breaker_mode.dart';

enum BrickBreakerLeaderboardSource { pc, public }

class LeaderboardEntry {
  final int rank;
  final String name;
  final int score;
  final int ts;

  const LeaderboardEntry({
    required this.rank,
    required this.name,
    required this.score,
    required this.ts,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '?',
      score: (json['score'] as num?)?.toInt() ?? 0,
      ts: (json['ts'] as num?)?.toInt() ?? 0,
    );
  }
}

class LeaderboardFetchResult {
  final bool ok;
  final List<LeaderboardEntry> entries;
  final String? error;

  const LeaderboardFetchResult({
    required this.ok,
    this.entries = const [],
    this.error,
  });
}

class LeaderboardSubmitResult {
  final bool ok;
  final int? rank;
  final String? error;

  const LeaderboardSubmitResult({required this.ok, this.rank, this.error});
}

class BrickBreakerLeaderboardService {
  static const nameKey = 'zs_brick_breaker_lb_name';

  final SettingsService _settings;

  BrickBreakerLeaderboardService({SettingsService? settings})
      : _settings = settings ?? SettingsService();

  Future<String?> getName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(nameKey);
  }

  Future<String> setName(String raw) async {
    final clean = _sanitizeName(raw);
    final prefs = await SharedPreferences.getInstance();
    if (clean.isEmpty) {
      await prefs.remove(nameKey);
    } else {
      await prefs.setString(nameKey, clean);
    }
    return clean;
  }

  String _sanitizeName(String raw) {
    var s = raw.trim().replaceAll(RegExp(r"[^\w\s\-'.]"), '').trim();
    if (s.length > 20) s = s.substring(0, 20);
    return s;
  }

  Future<String?> resolveApiBase() async {
    final source = await getSource();
    if (source == BrickBreakerLeaderboardSource.public) {
      final public = await _settings.getBrickBreakerLeaderboardUrl();
      if (public == null || public.isEmpty) return null;
      return public.replaceFirst(RegExp(r'/+$'), '');
    }
    return _settings.baseUrl('brick_breaker');
  }

  Future<BrickBreakerLeaderboardSource> getSource() async {
    final key = await _settings.getBrickBreakerLeaderboardSourceKey();
    return key == 'public'
        ? BrickBreakerLeaderboardSource.public
        : BrickBreakerLeaderboardSource.pc;
  }

  Future<void> setSource(BrickBreakerLeaderboardSource source) =>
      _settings.setBrickBreakerLeaderboardSourceKey(
        source == BrickBreakerLeaderboardSource.public ? 'public' : 'pc',
      );

  Future<String> describeConnection() async {
    final source = await getSource();
    if (source == BrickBreakerLeaderboardSource.public) {
      final url = await _settings.getBrickBreakerLeaderboardUrl();
      if (url == null || url.isEmpty) return 'Public board — add API URL below';
      return 'Public: $url';
    }
    final pc = await _settings.baseUrl('brick_breaker');
    if (pc == null || pc.isEmpty) {
      return 'My PC — set Tailscale hostname in app settings';
    }
    return 'My PC: $pc';
  }

  Future<LeaderboardFetchResult> fetch({
    required BrickBreakerMode mode,
    int limit = 25,
  }) async {
    final base = await resolveApiBase();
    if (base == null) {
      return const LeaderboardFetchResult(ok: false, error: 'offline');
    }
    final modeKey = mode == BrickBreakerMode.siege ? 'siege' : 'endless';
    try {
      final uri = Uri.parse('$base/api/leaderboard').replace(
        queryParameters: {
          'mode': modeKey,
          'limit': '$limit',
        },
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        return const LeaderboardFetchResult(ok: false, error: 'offline');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        return const LeaderboardFetchResult(ok: false, error: 'offline');
      }
      final rows = (data['entries'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(LeaderboardEntry.fromJson)
          .toList();
      return LeaderboardFetchResult(ok: true, entries: rows);
    } catch (_) {
      return const LeaderboardFetchResult(ok: false, error: 'offline');
    }
  }

  Future<LeaderboardSubmitResult> submit({
    required BrickBreakerMode mode,
    required int score,
    String? name,
  }) async {
    final player = _sanitizeName(name ?? (await getName()) ?? '');
    if (player.isEmpty) {
      return const LeaderboardSubmitResult(ok: false, error: 'no_name');
    }
    if (score < 1) {
      return const LeaderboardSubmitResult(ok: false, error: 'no_score');
    }
    final base = await resolveApiBase();
    if (base == null) {
      return const LeaderboardSubmitResult(ok: false, error: 'offline');
    }
    final modeKey = mode == BrickBreakerMode.siege ? 'siege' : 'endless';
    try {
      final res = await http
          .post(
            Uri.parse('$base/api/leaderboard'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'mode': modeKey, 'name': player, 'score': score}),
          )
          .timeout(const Duration(seconds: 8));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200 || data['ok'] != true) {
        return LeaderboardSubmitResult(
          ok: false,
          error: data['error'] as String? ?? 'failed',
        );
      }
      return LeaderboardSubmitResult(
        ok: true,
        rank: (data['rank'] as num?)?.toInt(),
      );
    } catch (_) {
      return const LeaderboardSubmitResult(ok: false, error: 'offline');
    }
  }

  static String formatScore(int n) {
    if (n >= 1000000) {
      return '${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1)}M';
    }
    if (n >= 10000) return '${(n / 1000).round()}k';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  static String formatWhen(int ts) {
    if (ts <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}';
  }
}
