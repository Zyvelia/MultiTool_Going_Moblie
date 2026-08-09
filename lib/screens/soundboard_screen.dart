import 'package:flutter/material.dart';
import '../models/sound_clip.dart';
import '../services/settings_service.dart';
import '../services/soundboard_api_service.dart';

class SoundboardScreen extends StatefulWidget {
  const SoundboardScreen({super.key});

  @override
  State<SoundboardScreen> createState() => _SoundboardScreenState();
}

class _SoundboardScreenState extends State<SoundboardScreen> {
  final _settings = SettingsService();
  SoundboardApiService? _api;
  List<SoundClip> _sounds = [];
  bool _loading = true;
  String? _error;
  String? _playingId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final base = await _settings.baseUrl('soundboard');
    final code = await _settings.getAccessCode('soundboard');
    if (base == null) return;
    setState(() => _api = SoundboardApiService(base, accessCode: code));
    await _load();
  }

  Future<void> _load() async {
    if (_api == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await _api!.fetchStatus();
      if (status != null && status['folder_valid'] != true) {
        setState(() {
          _error = 'No sound folder set yet. Pick one from the Soundboard '
              'page on your PC (Load Folder), then pull to refresh here.';
          _loading = false;
          _sounds = [];
        });
        return;
      }
      final sounds = await _api!.fetchSounds();
      setState(() {
        _sounds = sounds;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not reach Soundboard: ${e.toString().replaceFirst('Exception: ', '')}';
        _loading = false;
      });
    }
  }

  Future<void> _play(SoundClip sound) async {
    if (_api == null) return;
    setState(() => _playingId = sound.id);
    try {
      await _api!.play(sound.id);
    } catch (e) {
      _showToast(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) setState(() => _playingId = null);
        });
      }
    }
  }

  Future<void> _stopAll() async {
    if (_api == null) return;
    try {
      await _api!.stopAll();
    } catch (e) {
      _showToast(e.toString().replaceFirst('Exception: ', ''));
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
        title: Text(_sounds.isNotEmpty ? '${_sounds.length} sounds' : 'Soundboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined),
            tooltip: 'Stop all',
            onPressed: _stopAll,
          ),
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
                            style: const TextStyle(color: Colors.white54),
                            textAlign: TextAlign.center),
                      ),
                    ],
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1.1,
                    ),
                    itemCount: _sounds.length,
                    itemBuilder: (context, i) {
                      final s = _sounds[i];
                      final playing = _playingId == s.id;
                      return Material(
                        color: playing
                            ? const Color(0xFF23304a)
                            : const Color(0xFF1B2030),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _play(s),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  playing ? Icons.graphic_eq : Icons.volume_up,
                                  color: playing
                                      ? const Color(0xFF4EA1FF)
                                      : Colors.white54,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  s.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
