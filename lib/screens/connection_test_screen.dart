import 'package:flutter/material.dart';
import '../services/connection_test_service.dart';
import '../services/settings_service.dart';

class ConnectionTestScreen extends StatefulWidget {
  const ConnectionTestScreen({super.key});

  @override
  State<ConnectionTestScreen> createState() => _ConnectionTestScreenState();
}

class _ConnectionTestScreenState extends State<ConnectionTestScreen> {
  final _settings = SettingsService();
  final _tester = ConnectionTestService();

  String? _privateUrl;
  String? _publicUrl;
  List<ConnectionTestStep>? _privateResults;
  List<ConnectionTestStep>? _publicResults;
  bool _runningPrivate = false;
  bool _runningPublic = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final private = await _settings.getMusicPrivateUrl();
    final public = await _settings.getMusicPublicUrl();
    setState(() {
      _privateUrl = private;
      _publicUrl = public;
    });
    if (private != null) _runPrivate();
    if (public != null) _runPublic();
  }

  Future<void> _runPrivate() async {
    if (_privateUrl == null) return;
    setState(() => _runningPrivate = true);
    final results = await _tester.run(_privateUrl!);
    if (!mounted) return;
    setState(() {
      _privateResults = results;
      _runningPrivate = false;
    });
  }

  Future<void> _runPublic() async {
    if (_publicUrl == null) return;
    setState(() => _runningPublic = true);
    final results = await _tester.run(_publicUrl!);
    if (!mounted) return;
    setState(() {
      _publicResults = results;
      _runningPublic = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connection test')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ServerSection(
            title: 'Private (Tailscale)',
            url: _privateUrl,
            running: _runningPrivate,
            results: _privateResults,
            onRetest: _runPrivate,
          ),
          const SizedBox(height: 20),
          _ServerSection(
            title: 'Public',
            url: _publicUrl,
            running: _runningPublic,
            results: _publicResults,
            onRetest: _runPublic,
          ),
        ],
      ),
    );
  }
}

class _ServerSection extends StatelessWidget {
  final String title;
  final String? url;
  final bool running;
  final List<ConnectionTestStep>? results;
  final VoidCallback onRetest;

  const _ServerSection({
    required this.title,
    required this.url,
    required this.running,
    required this.results,
    required this.onRetest,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                if (url != null)
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Re-test',
                    onPressed: running ? null : onRetest,
                  ),
              ],
            ),
            if (url == null)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Not configured in Settings',
                    style: TextStyle(color: Colors.white38)),
              )
            else if (running)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (results != null)
              Column(
                children: results!.map((s) => _StepRow(step: s)).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final ConnectionTestStep step;
  const _StepRow({required this.step});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (step.status) {
      StepStatus.pass => (Icons.check_circle, Colors.greenAccent),
      StepStatus.fail => (Icons.error, Colors.redAccent),
      StepStatus.skipped => (Icons.remove_circle_outline, Colors.white38),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  step.latencyMs != null
                      ? '${step.detail} (${step.latencyMs}ms)'
                      : step.detail,
                  style: const TextStyle(color: Colors.white54, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
