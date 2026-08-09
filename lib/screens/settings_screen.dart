import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService();
  final _hostController = TextEditingController();
  final _gamesCodeController = TextEditingController();
  final _soundboardCodeController = TextEditingController();
  final _ytCodeController = TextEditingController();

  bool _loaded = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final host = await _settings.getHostname();
    final gamesCode = await _settings.getAccessCode('games');
    final soundboardCode = await _settings.getAccessCode('soundboard');
    final ytCode = await _settings.getAccessCode('yt');
    _hostController.text = host ?? '';
    _gamesCodeController.text = gamesCode ?? '';
    _soundboardCodeController.text = soundboardCode ?? '';
    _ytCodeController.text = ytCode ?? '';
    setState(() => _loaded = true);
  }

  Future<void> _save() async {
    final host = _hostController.text.trim();
    if (host.isEmpty) return;
    await _settings.setHostname(host);
    await _settings.setAccessCode('games', _gamesCodeController.text);
    await _settings.setAccessCode('soundboard', _soundboardCodeController.text);
    await _settings.setAccessCode('yt', _ytCodeController.text);
    setState(() => _saved = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved')),
      );
    }
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset settings?'),
        content: const Text(
          'This clears your saved Tailscale hostname and all access codes '
          'from this device. You\'ll need to re-enter them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _settings.clearAll();
    _hostController.clear();
    _gamesCodeController.clear();
    _soundboardCodeController.clear();
    _ytCodeController.clear();
    setState(() => _saved = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings cleared')),
      );
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _gamesCodeController.dispose();
    _soundboardCodeController.dispose();
    _ytCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Enter your PC\'s Tailscale hostname — the same one shown in '
            'each module\'s Settings tab when Remote Access is on. '
            'Example: my-pc.tailnet-name.ts.net (no https://, no port — '
            'each module has its own fixed port already built in).',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _hostController,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Tailscale hostname',
              hintText: 'my-pc.tailnet-name.ts.net',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Access codes (optional)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            'Only needed if you set one in the matching module\'s Settings '
            'tab on the desktop app. Leave blank otherwise.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _gamesCodeController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Gaming Hub code',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _soundboardCodeController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Soundboard code',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ytCodeController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'YouTube Downloader code',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _save,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Save'),
            ),
          ),
          if (_saved) ...[
            const SizedBox(height: 8),
            const Text(
              'If a module screen is already open, switch tabs to reconnect '
              'with the new settings.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
          const SizedBox(height: 28),
          const Divider(color: Colors.white24),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _reset,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Reset settings'),
            ),
          ),
        ],
      ),
    );
  }
}
