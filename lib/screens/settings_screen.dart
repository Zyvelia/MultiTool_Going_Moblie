import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  final String? initialUrl;
  const SettingsScreen({super.key, this.initialUrl});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _controller;
  final _settings = SettingsService();
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl ?? '');
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final url = _controller.text.trim().replaceAll(RegExp(r'/+$'), '');
    final ok = await ApiService(url).checkStatus();
    setState(() {
      _testing = false;
      _testResult = ok ? 'Connected!' : "Couldn't reach that address.";
    });
  }

  Future<void> _save() async {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    await _settings.setServerUrl(url);
    if (mounted) Navigator.of(context).pop(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Server')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the Tailscale address shown in the desktop app\'s '
              'Music Player > Settings tab when Remote Access is on. '
              'Example: https://my-pc.tailnet-name.ts.net:8444',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'https://my-pc.tailnet-name.ts.net:8444',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _testing ? null : _testConnection,
                  child: Text(_testing ? 'Testing…' : 'Test connection'),
                ),
                const SizedBox(width: 12),
                if (_testResult != null)
                  Text(
                    _testResult!,
                    style: TextStyle(
                      color: _testResult == 'Connected!'
                          ? Colors.greenAccent
                          : Colors.redAccent,
                    ),
                  ),
              ],
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Save'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
