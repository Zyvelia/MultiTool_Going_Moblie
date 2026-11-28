import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/live_server_client.dart';

class LiveServerScreen extends StatefulWidget {
  const LiveServerScreen({super.key});
  @override
  State<LiveServerScreen> createState() => _LiveServerScreenState();
}

class _LiveServerScreenState extends State<LiveServerScreen> with WidgetsBindingObserver {
  final _url = TextEditingController();
  final _code = TextEditingController();
  LiveServerClient? _client;
  Map<String, dynamic>? _state;
  Timer? _timer;
  bool _busy = false;
  bool _foreground = true;
  bool _showCode = false;
  String? _error;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadAddress());
  }

  Future<void> _loadAddress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted && _url.text.isEmpty) {
        _url.text = prefs.getString('live_server_url_v1') ?? '';
      }
    } catch (_) { /* Address persistence is optional. */ }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _timer?.cancel();
    } else if (_client != null) {
      _schedule(Duration.zero);
    }
  }

  void _schedule([Duration delay = const Duration(seconds: 3)]) {
    _timer?.cancel();
    if (mounted && _foreground && _client != null) {
      _timer = Timer(delay, () => unawaited(_refresh()));
    }
  }

  String _message(Object e) {
    if (e is FormatException) return e.message;
    if (e is LiveServerException) return e.message;
    return 'Cannot reach ZMT. Check Tailscale on both devices, the server URL, and Windows firewall permissions.';
  }

  Future<void> _connect() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    final epoch = ++_epoch;
    setState(() { _busy = true; _error = null; _state = null; });
    try {
      final client = LiveServerClient(_url.text, _code.text);
      final data = await client.connect();
      if (!mounted || epoch != _epoch) return;
      setState(() { _client = client; _state = data; _code.clear(); _showCode = false; });
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('live_server_url_v1', client.base.toString());
      } catch (_) { /* Never persist the session code. */ }
    } catch (e) {
      if (mounted && epoch == _epoch) setState(() => _error = _message(e));
    } finally {
      if (mounted && epoch == _epoch) {
        setState(() => _busy = false);
        _schedule();
      }
    }
  }

  Future<void> _refresh() async {
    final client = _client;
    if (client == null || !_foreground) return;
    if (_busy) { _schedule(); return; }
    final epoch = _epoch;
    _busy = true;
    try {
      final data = await client.state();
      if (mounted && epoch == _epoch) {
        setState(() { _state = data; _error = null; });
      }
    } catch (e) {
      if (mounted && epoch == _epoch) {
        setState(() {
          _state = null;
          _error = _message(e);
          if (e is LiveServerException && e.message.startsWith('Access code')) {
            _client = null;
          }
        });
      }
    } finally {
      if (mounted && epoch == _epoch) {
        setState(() => _busy = false);
        _schedule(_error == null ? const Duration(seconds: 3) : const Duration(seconds: 8));
      }
    }
  }

  void _disconnect() {
    ++_epoch;
    _timer?.cancel();
    setState(() {
      _client = null; _state = null; _error = null; _busy = false;
      _code.clear(); _showCode = false;
    });
  }

  @override
  void dispose() {
    ++_epoch;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _url.dispose();
    _code.dispose();
    _client = null;
    super.dispose();
  }

  String _time(Object? value) {
    final s = value is num && value.isFinite && value >= 0 ? value.toInt() : 0;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final data = _state;
    final modules = (data?['modules'] as List? ?? const []).whereType<Map>();
    final media = data?['media'] as Map?;
    final connected = _client != null;
    return Scaffold(
      appBar: AppBar(title: const Text('ZMT Live Server')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data != null ? 'Connected' : connected ? 'Reconnecting' : 'Private connection',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Connect both devices to Tailscale. On PC open ZMT → Live Server, select its Tailscale adapter, start the server and copy its URL and code.'),
            const SizedBox(height: 16),
            if (!connected) ...[
              TextField(controller: _url, enabled: !_busy,
                keyboardType: TextInputType.url, autocorrect: false,
                decoration: const InputDecoration(labelText: 'Live Server URL', hintText: 'http://100.64.1.23:8790', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _code, enabled: !_busy, obscureText: !_showCode,
                autocorrect: false, enableSuggestions: false,
                decoration: InputDecoration(labelText: 'Session access code', border: const OutlineInputBorder(),
                  suffixIcon: IconButton(tooltip: _showCode ? 'Hide code' : 'Show code',
                    icon: Icon(_showCode ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showCode = !_showCode)))),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: _busy ? null : _connect,
                icon: const Icon(Icons.link), label: Text(_busy ? 'Connecting…' : 'Connect')),
            ] else ...[
              Text(_client!.base.toString()),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: _disconnect, icon: const Icon(Icons.link_off), label: const Text('Disconnect')),
            ],
            if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
          ],
        ))),
        if (data != null) ...[
          const SizedBox(height: 12),
          Text('Desktop · v${data['version']}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(child: ListTile(leading: const Icon(Icons.music_note),
            title: Text(media == null ? 'Music status not shared' : '${media['title'] ?? ''}'),
            subtitle: Text(media == null ? 'Enable music status on the PC Live Server page.' :
              '${media['detail'] ?? ''}\n${media['playing'] == true ? 'Playing' : 'Paused'} · ${_time(media['position'])} / ${_time(media['duration'])}'))),
          const SizedBox(height: 12),
          Text('Installed modules (${modules.length})', style: Theme.of(context).textTheme.titleLarge),
          for (final module in modules)
            Card(child: ListTile(
              leading: Icon(module['active'] == true ? Icons.radio_button_checked : Icons.extension_outlined),
              title: Text('${module['name'] ?? module['id'] ?? 'Module'}'),
              subtitle: Text('v${module['version'] ?? '?'}'),
              trailing: Text(module['active'] == true ? 'Active' : 'Installed'))),
          const SizedBox(height: 12),
          const Text('Protocol 1 · Read-only status. Library streaming, remote actions and module data sync are not available yet.'),
        ],
        const SizedBox(height: 12),
        const Text('The code is kept only while this screen is open. The PC rotates it on each server restart. Do not forward this port to the internet.'),
      ]),
    );
  }
}
