import 'package:flutter/material.dart';
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
    if (base == null) return;
    setState(() => _api = GamesApiService(base, accessCode: code));
    await _load();
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

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_api == null) {
      return const Scaffold(
        body: Center(
          child: Text('Set your PC hostname in Settings first.',
              style: TextStyle(color: Colors.white54)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_games.isNotEmpty ? '${_games.length} games' : 'Gaming Hub'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _rescan),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!,
                            style: const TextStyle(color: Colors.redAccent),
                            textAlign: TextAlign.center),
                      ),
                    ],
                  )
                : _games.isEmpty
                    ? ListView(
                        children: const [
                          Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No games found. Try scanning from the Gaming Hub '
                              'page on your PC, or tap the refresh icon above.',
                              style: TextStyle(color: Colors.white54),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        itemCount: _games.length,
                        itemBuilder: (context, i) {
                          final g = _games[i];
                          final launching = _launchingId == g.id;
                          return ListTile(
                            leading: const Icon(Icons.sports_esports,
                                color: AppColors.accent),
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
                        },
                      ),
      ),
    );
  }
}
