import 'package:flutter/material.dart';
import '../models/server_profile.dart';
import '../services/device_trust_service.dart';
import '../services/settings_service.dart';
import '../services/user_facing_error.dart';
import 'connection_test_screen.dart';
import 'speed_test_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService();
  final _hostController = TextEditingController();
  final _gamesCodeController = TextEditingController();
  final _ytCodeController = TextEditingController();
  final _gsmCodeController = TextEditingController();
  final _inviteController = TextEditingController();
  final _chatCodeController = TextEditingController();
  final _musicPublicUrlController = TextEditingController();
  final _pairCodeController = TextEditingController();
  final _pairLabelController = TextEditingController(text: 'phone');

  bool _paired = false;
  bool _pairing = false;
  String? _pairMessage;

  PreferredServer _musicPreferred = PreferredServer.auto;
  bool _musicWifiOnly = true;

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
    final ytCode = await _settings.getAccessCode('yt');
    final gsmCode = await _settings.getAccessCode('gsm');
    final invite = await _settings.getSocialInviteKey();
    final chatCode = await _settings.getAccessCode('chat');
    final musicPublicUrl = await _settings.getMusicPublicUrl();
    final musicPreferred = await _settings.getMusicPreferredServer();
    final musicWifiOnly = await _settings.getMusicWifiOnlyDownloads();
    _hostController.text = host ?? '';
    _gamesCodeController.text = gamesCode ?? '';
    _ytCodeController.text = ytCode ?? '';
    _gsmCodeController.text = gsmCode ?? '';
    _inviteController.text = invite ?? '';
    _chatCodeController.text = chatCode ?? '';
    _musicPublicUrlController.text = musicPublicUrl ?? '';
    final paired = await deviceTrust.isPaired();
    setState(() {
      _musicPreferred = musicPreferred;
      _musicWifiOnly = musicWifiOnly;
      _paired = paired;
      _loaded = true;
    });
  }

  Future<void> _pairPhone() async {
    final host = _hostController.text.trim();
    final code = _pairCodeController.text.trim();
    if (host.isEmpty || code.isEmpty) {
      setState(() => _pairMessage = 'Save a Tailscale hostname and the 6-digit code from Remote Hub.');
      return;
    }
    setState(() {
      _pairing = true;
      _pairMessage = null;
    });
    try {
      await _settings.setHostname(host);
      await deviceTrust.pair(host, code, label: _pairLabelController.text);
      if (!mounted) return;
      setState(() {
        _paired = true;
        _pairing = false;
        _pairMessage = 'Paired. If this phone is stolen, revoke it on Remote Hub.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pairing = false;
        _pairMessage = explainError(e, doing: 'pair this phone');
      });
    }
  }

  Future<void> _forgetPairing() async {
    await deviceTrust.clearSecret();
    if (!mounted) return;
    setState(() {
      _paired = false;
      _pairMessage = 'Forgot the secret on this phone. The PC still lists it until you revoke.';
    });
  }

  Future<void> _save() async {
    final host = _hostController.text.trim();
    if (host.isEmpty) return;
    await _settings.setHostname(host);
    await _settings.setAccessCode('games', _gamesCodeController.text);
    await _settings.setAccessCode('yt', _ytCodeController.text);
    await _settings.setAccessCode('gsm', _gsmCodeController.text);
    await _settings.setSocialInviteKey(_inviteController.text);
    await _settings.setAccessCode('chat', _chatCodeController.text);
    await _settings.setMusicPublicUrl(_musicPublicUrlController.text);
    await _settings.setMusicPreferredServer(_musicPreferred);
    await _settings.setMusicWifiOnlyDownloads(_musicWifiOnly);
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
    _ytCodeController.clear();
    _gsmCodeController.clear();
    _inviteController.clear();
    _chatCodeController.clear();
    _musicPublicUrlController.clear();
    setState(() {
      _musicPreferred = PreferredServer.auto;
      _musicWifiOnly = true;
      _saved = false;
    });
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
    _ytCodeController.dispose();
    _gsmCodeController.dispose();
    _inviteController.dispose();
    _chatCodeController.dispose();
    _musicPublicUrlController.dispose();
    _pairCodeController.dispose();
    _pairLabelController.dispose();
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
            'This phone',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            'Pair with a code from Remote Hub on the PC. If the phone is '
            'lost, revoke it there — that copy of the app stops. This does '
            'not detect malware on the handset.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Text(
            _paired ? 'Paired to this PC' : 'Not paired yet',
            style: TextStyle(
              color: _paired ? Colors.greenAccent : Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pairCodeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'Pairing code',
              hintText: '6 digits from Remote Hub',
              border: OutlineInputBorder(),
              counterText: '',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pairLabelController,
            decoration: const InputDecoration(
              labelText: 'Name on the PC',
              hintText: 'phone',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _pairing ? null : _pairPhone,
            child: Text(_pairing ? 'Pairing…' : 'Pair this phone'),
          ),
          if (_paired) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _forgetPairing,
              child: const Text('Forget pairing on this phone'),
            ),
          ],
          if (_pairMessage != null) ...[
            const SizedBox(height: 8),
            Text(_pairMessage!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
          const SizedBox(height: 28),
          const Text(
            'Music server',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            'Optional: a public HTTPS API for the music library, for when '
            'you\'re away from the tailnet (e.g. Tailscale not installed '
            'on this device). Leave blank to use Tailscale only.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _musicPublicUrlController,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Public music API URL',
              hintText: 'https://music.example.com/api',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Preferred server', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          SegmentedButton<PreferredServer>(
            segments: const [
              ButtonSegment(value: PreferredServer.auto, label: Text('Auto')),
              ButtonSegment(value: PreferredServer.private, label: Text('Private')),
              ButtonSegment(value: PreferredServer.public, label: Text('Public')),
            ],
            selected: {_musicPreferred},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _musicPreferred = s.first),
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Wi-Fi-only downloads'),
            subtitle: const Text(
              'Avoid downloading music for offline use on cellular',
              style: TextStyle(fontSize: 12),
            ),
            value: _musicWifiOnly,
            onChanged: (v) => setState(() => _musicWifiOnly = v),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ConnectionTestScreen()),
            ),
            icon: const Icon(Icons.wifi_tethering),
            label: const Text('Test connection'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SpeedTestScreen()),
            ),
            icon: const Icon(Icons.speed),
            label: const Text('Speed test'),
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
            controller: _ytCodeController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'YouTube Downloader code',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _gsmCodeController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Game servers code (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _inviteController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Night invite key',
              hintText: 'From Tailnet Social on the PC',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _chatCodeController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'AI Chat code (optional)',
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
