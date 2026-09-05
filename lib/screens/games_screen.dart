import 'package:flutter/material.dart';
import '../games/brick_breaker/brick_breaker_menu_screen.dart';
import '../games/neon_drift/neon_drift_screen.dart';
import '../models/game.dart';
import '../models/game_server.dart';
import '../theme/app_colors.dart';
import '../services/settings_service.dart';
import '../services/games_api_service.dart';
import '../services/gsm_api_service.dart';
import '../services/user_facing_error.dart';
import 'night_screen.dart';

class GamesScreen extends StatefulWidget {
  const GamesScreen({super.key});

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  final _settings = SettingsService();
  GamesApiService? _api;
  GsmApiService? _gsm;
  List<Game> _games = [];
  List<GameServer> _servers = [];
  bool _loading = true;
  bool _serversLoading = false;
  String? _error;
  String? _serversError;
  String? _launchingId;
  String? _busyServerId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final base = await _settings.baseUrl('games');
    final code = await _settings.getAccessCode('games');
    final gsmBase = await _settings.baseUrl('gsm');
    final gsmCode = await _settings.getAccessCode('gsm');
    if (base != null) {
      setState(() => _api = GamesApiService(base, accessCode: code));
    }
    if (gsmBase != null) {
      setState(() => _gsm = GsmApiService(gsmBase, accessCode: gsmCode));
    }
    if (_api != null) {
      await _load();
    } else {
      setState(() => _loading = false);
    }
    await _loadServers();
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
        _error = explainError(e, doing: 'reach Gaming Hub');
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
      _showToast(explainError(e));
    }
  }

  Future<void> _launch(Game game) async {
    if (_api == null) return;
    setState(() => _launchingId = game.id);
    try {
      await _api!.launch(game.id);
      _showToast('Launching ${game.name}…');
    } catch (e) {
      _showToast(explainError(e));
    } finally {
      if (mounted) setState(() => _launchingId = null);
    }
  }

  void _openNeonDrift() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NeonDriftScreen()),
    );
  }

  Future<void> _loadServers() async {
    if (_gsm == null) return;
    setState(() {
      _serversLoading = true;
      _serversError = null;
    });
    try {
      final servers = await _gsm!.fetchServers();
      setState(() {
        _servers = servers;
        _serversLoading = false;
      });
    } catch (e) {
      setState(() {
        _serversError = explainError(e, doing: 'reach Game Server Manager');
        _serversLoading = false;
      });
    }
  }

  Future<void> _toggleServer(GameServer server) async {
    if (_gsm == null) return;
    setState(() => _busyServerId = server.id);
    try {
      if (server.running) {
        await _gsm!.stop(server.id);
        _showToast('Stopping ${server.name}…');
      } else {
        await _gsm!.start(server.id);
        _showToast('Starting ${server.name}…');
      }
      await Future.delayed(const Duration(seconds: 1));
      await _loadServers();
    } catch (e) {
      _showToast(explainError(e));
    } finally {
      if (mounted) setState(() => _busyServerId = null);
    }
  }

  void _openNight() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NightScreen()),
    );
  }

  void _openBrickBreaker() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BrickBreakerMenuScreen()),
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
              child: const Icon(Icons.nights_stay, color: AppColors.accent),
            ),
            title: const Text('Night page'),
            subtitle: const Text(
              'Jukebox, soundboard, limited console',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: AppColors.accent),
            onTap: _openNight,
          ),
        ),
      ],
    );
  }

  Widget _serversSection() {
    if (_gsm == null) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          'Set your PC hostname, then Hub Go Live, to start/stop dedicated servers from here.',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
      );
    }
    if (_serversLoading && _servers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_serversError != null && _servers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          _serversError!,
          style: const TextStyle(color: Colors.redAccent),
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
            'DEDICATED SERVERS · ${_servers.length}',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
        ),
        if (_servers.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'No servers saved in Game Server Manager yet.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          )
        else
          ..._servers.map((s) {
            final busy = _busyServerId == s.id;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ListTile(
                leading: Icon(
                  s.ready
                      ? Icons.dns
                      : s.running
                          ? Icons.hourglass_top
                          : Icons.dns_outlined,
                  color: s.ready
                      ? Colors.lightGreenAccent
                      : s.running
                          ? Colors.amber
                          : AppColors.muted,
                ),
                title: Text(s.name),
                subtitle: Text(
                  [
                    s.gameType,
                    s.statusLabel,
                    if (s.players.isNotEmpty) '${s.players.length} on',
                  ].where((p) => p.isNotEmpty).join(' · '),
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton(
                        onPressed: () => _toggleServer(s),
                        child: Text(s.running ? 'Stop' : 'Start'),
                      ),
              ),
            );
          }),
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
          if (_api != null || _gsm != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                await _rescan();
                await _loadServers();
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _load();
          await _loadServers();
        },
        child: ListView(
          children: [
            _localGamesSection(),
            _serversSection(),
            _pcHubSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
