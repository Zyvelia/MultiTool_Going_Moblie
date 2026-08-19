import 'package:flutter/material.dart';
import '../games/brick_breaker/brick_breaker_screen.dart';
import '../games/neon_drift/neon_drift_screen.dart';
import '../models/game.dart';
import '../theme/app_colors.dart';
import '../services/settings_service.dart';
import '../services/games_api_service.dart';

class GamesScreen extends StatefulWidget {
  const GamesScreen({super.key});

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  final _settings = SettingsService();
  GamesApiService? _api;
  List<Game> _games = [];
  bool _loading = true;
  String? _error;
  String? _launchingId;
  String? _toast;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final base = await _settings.baseUrl('games');
    final code = await _settings.getAccessCode('games');
    if (base != null) {
      setState(() => _api = GamesApiService(base, accessCode: code));
      await _load();
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _load() async {
    if (_api == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final games = await _api!.fetchGames();
      setState(() {
        _games = games;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not reach Gaming Hub: ${e.toString().replaceFirst('Exception: ', '')}';
        _loading = false;
      });
    }
  }

  Future<void> _rescan() async {
    if (_api == null) return;
    try {
      await _api!.rescan();
      _showToast('Rescanning on your PC…');
      await Future.delayed(const Duration(seconds: 3));
      await _load();
    } catch (e) {
      _showToast(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _launch(Game game) async {
    if (_api == null) return;
    setState(() => _launchingId = game.id);
    try {
      await _api!.launch(game.id);
      _showToast('Launching ${game.name}…');
    } catch (e) {
      _showToast(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _launchingId = null);
    }
  }

  void _openNeonDrift() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NeonDriftScreen()),
    );
  }

  void _openBrickBreaker() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BrickBreakerScreen()),
    );
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Widget _localGamesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'ON THIS PHONE',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.accentMuted,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
              ),
              child: const Icon(Icons.sports_baseball, color: AppColors.accent),
            ),
            title: const Text('Brick Breaker'),
            subtitle: const Text(
              'Neon brick shooter · works offline',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.play_arrow, color: AppColors.accent),
            onTap: _openBrickBreaker,
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.accentMuted,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
              ),
              child: const Icon(Icons.blur_linear, color: AppColors.accent),
            ),
            title: const Text('Neon Drift'),
            subtitle: const Text(
              'Endless gap dodge · works offline',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.play_arrow, color: AppColors.accent),
            onTap: _openNeonDrift,
          ),
        ),
      ],
    );
  }

  Widget _pcHubSection() {
    if (_api == null) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          'Set your PC hostname in Settings to remote-launch games from the Gaming Hub.',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
      );
    }

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          _error!,
          style: const TextStyle(color: Colors.redAccent),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (_games.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No PC games found. Try scanning from the Gaming Hub page on your desktop, '
          'or tap refresh above.',
          style: TextStyle(color: Colors.white54),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'PC GAMING HUB · ${_games.length}',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
        ),
        ..._games.map((g) {
          final launching = _launchingId == g.id;
          return ListTile(
            leading: const Icon(Icons.sports_esports, color: AppColors.accent),
            title: Text(g.name),
            subtitle: Text(g.launcher),
            trailing: launching
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            onTap: launching ? null : () => _launch(g),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Games'),
        actions: [
          if (_api != null)
            IconButton(icon: const Icon(Icons.refresh), onPressed: _rescan),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            _localGamesSection(),
            _pcHubSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
