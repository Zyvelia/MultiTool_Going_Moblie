import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/social_api_service.dart';
import '../services/user_facing_error.dart';
import '../theme/app_colors.dart';

class NightScreen extends StatefulWidget {
  const NightScreen({super.key});

  @override
  State<NightScreen> createState() => _NightScreenState();
}

class _NightScreenState extends State<NightScreen> {
  final _settings = SettingsService();
  final _keyController = TextEditingController();
  final _trackController = TextEditingController();
  final _soundController = TextEditingController();
  final _serverController = TextEditingController();
  final _cmdController = TextEditingController();

  SocialApiService? _api;
  List<Map<String, dynamic>> _queue = [];
  List<String> _sounds = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _trackController.dispose();
    _soundController.dispose();
    _serverController.dispose();
    _cmdController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final saved = await _settings.getSocialInviteKey();
    _keyController.text = saved ?? '';
    await _connect();
  }

  Future<void> _connect() async {
    final base = await _settings.baseUrl('social');
    final key = _keyController.text.trim();
    if (base == null) {
      setState(() {
        _loading = false;
        _error = 'Set your PC hostname in Settings.';
        _api = null;
      });
      return;
    }
    if (key.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Paste an invite key from Tailnet Social on the PC.';
        _api = null;
      });
      return;
    }
    await _settings.setSocialInviteKey(key);
    setState(() {
      _api = SocialApiService(base, inviteKey: key);
      _error = null;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    if (_api == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final queue = await _api!.fetchQueue();
      List<String> sounds = [];
      try {
        sounds = await _api!.fetchSounds();
      } catch (_) {}
      setState(() {
        _queue = queue;
        _sounds = sounds;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = explainError(e);
        _loading = false;
      });
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _addTrack() async {
    final title = _trackController.text.trim();
    if (title.isEmpty || _api == null) return;
    try {
      await _api!.addToQueue(title);
      _trackController.clear();
      await _refresh();
    } catch (e) {
      _toast(explainError(e));
    }
  }

  Future<void> _play(String name) async {
    if (_api == null) return;
    try {
      await _api!.playSound(name);
      _toast('Playing $name');
    } catch (e) {
      _toast(explainError(e));
    }
  }

  Future<void> _console() async {
    if (_api == null) return;
    final server = _serverController.text.trim();
    final cmd = _cmdController.text.trim();
    if (server.isEmpty || cmd.isEmpty) return;
    try {
      await _api!.sendConsole(server, cmd);
      _cmdController.clear();
      _toast('Sent');
    } catch (e) {
      _toast(explainError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Night'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _keyController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Invite key',
              hintText: 'From Tailnet Social on the PC',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(onPressed: _connect, child: const Text('Use this key')),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          if (_loading) ...[
            const SizedBox(height: 32),
            const Center(child: CircularProgressIndicator()),
          ],
          if (!_loading && _api != null) ...[
            const SizedBox(height: 24),
            const Text(
              'JUKEBOX',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _trackController,
                    decoration: const InputDecoration(
                      hintText: 'Track or URL',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addTrack(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _addTrack, child: const Text('Add')),
              ],
            ),
            const SizedBox(height: 8),
            if (_queue.isEmpty)
              const Text('Queue is empty.', style: TextStyle(color: Colors.white54))
            else
              ..._queue.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.queue_music, color: AppColors.accent),
                  title: Text(item['title']?.toString() ?? ''),
                  subtitle: Text(item['by']?.toString() ?? ''),
                ),
              ),
            const SizedBox(height: 20),
            const Text(
              'SOUNDBOARD',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            if (_sounds.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _sounds
                    .map((n) => ActionChip(label: Text(n), onPressed: () => _play(n)))
                    .toList(),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _soundController,
                    decoration: const InputDecoration(
                      hintText: 'Clip name',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) => _play(v.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _play(_soundController.text.trim()),
                  child: const Text('Play'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'SERVER CONSOLE',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Only works if this invite key allows console.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _serverController,
              decoration: const InputDecoration(
                labelText: 'Server name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cmdController,
                    decoration: const InputDecoration(
                      hintText: 'say hello',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _console(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _console, child: const Text('Send')),
              ],
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
