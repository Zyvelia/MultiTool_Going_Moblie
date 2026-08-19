import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/connectivity_service.dart';
import '../services/settings_service.dart';
import '../services/speed_test_service.dart';

class SpeedTestScreen extends StatefulWidget {
  const SpeedTestScreen({super.key});

  @override
  State<SpeedTestScreen> createState() => _SpeedTestScreenState();
}

class _SpeedTestScreenState extends State<SpeedTestScreen> {
  final _settings = SettingsService();
  final _tester = SpeedTestService();

  NetworkType? _networkType;
  StreamSubscription<NetworkType>? _netSub;
  StreamSubscription<SpeedTestProgress>? _testSub;

  SpeedTestPhase _phase = SpeedTestPhase.idle;
  SpeedTestResult _result = const SpeedTestResult();
  double? _liveMbps;
  DateTime? _lastRunAt;

  @override
  void initState() {
    super.initState();
    _loadNetworkType();
    _netSub = ConnectivityService.instance.onChange.listen((type) {
      if (mounted) setState(() => _networkType = type);
    });
  }

  Future<void> _loadNetworkType() async {
    final type = await ConnectivityService.instance.current();
    if (mounted) setState(() => _networkType = type);
  }

  Future<void> _run() async {
    if (_networkType == NetworkType.offline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No network connection detected')),
      );
      return;
    }

    final serverUrl = await _settings.getMusicPrivateUrl();

    setState(() {
      _phase = SpeedTestPhase.ping;
      _result = const SpeedTestResult();
      _liveMbps = null;
    });

    await _testSub?.cancel();
    _testSub = _tester.run(serverBaseUrl: serverUrl).listen((progress) {
      if (!mounted) return;
      setState(() {
        _phase = progress.phase;
        _result = progress.result;
        _liveMbps = progress.liveMbps;
        if (progress.phase == SpeedTestPhase.done) {
          _lastRunAt = DateTime.now();
        }
      });
    });
  }

  bool get _running =>
      _phase == SpeedTestPhase.ping ||
      _phase == SpeedTestPhase.download ||
      _phase == SpeedTestPhase.upload;

  @override
  void dispose() {
    _netSub?.cancel();
    _testSub?.cancel();
    _tester.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Speed test')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _NetworkTypeBanner(type: _networkType),
          const SizedBox(height: 20),
          Center(
            child: SizedBox(
              width: 180,
              height: 180,
              child: _SpeedDial(
                phase: _phase,
                result: _result,
                liveMbps: _liveMbps,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              _phaseLabel(_phase),
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          const SizedBox(height: 24),
          _MetricRow(
            icon: Icons.speed,
            label: 'Ping',
            value: _result.pingMs == null
                ? '—'
                : '${_result.pingMs!.toStringAsFixed(0)} ms',
            sub: _result.jitterMs == null
                ? null
                : 'jitter ${_result.jitterMs!.toStringAsFixed(0)} ms'
                    '${_result.pingMinMs != null && _result.pingMaxMs != null ? ' · ${_result.pingMinMs!.toStringAsFixed(0)}–${_result.pingMaxMs!.toStringAsFixed(0)} ms' : ''}',
          ),
          if (_result.serverPingMs != null)
            _MetricRow(
              icon: Icons.dns,
              label: 'Home server ping',
              value: '${_result.serverPingMs!.toStringAsFixed(0)} ms',
              sub: 'Tailscale hop to your PC',
            ),
          _MetricRow(
            icon: Icons.arrow_downward,
            label: 'Download',
            value: _result.downloadMbps == null
                ? '—'
                : '${_result.downloadMbps!.toStringAsFixed(1)} Mbps',
          ),
          _MetricRow(
            icon: Icons.arrow_upward,
            label: 'Upload',
            value: _result.uploadMbps == null
                ? '—'
                : '${_result.uploadMbps!.toStringAsFixed(1)} Mbps',
          ),
          if (_phase == SpeedTestPhase.error)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _result.error ?? 'Speed test failed',
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _running ? null : _run,
            icon: _running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(_running
                ? 'Testing…'
                : (_phase == SpeedTestPhase.done ||
                        _phase == SpeedTestPhase.error
                    ? 'Test again'
                    : 'Start test')),
          ),
          if (_lastRunAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Center(
                child: Text(
                  'Last tested ${_formatTime(_lastRunAt!)}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'Tests against Cloudflare\'s public speed test endpoints — the '
            'same infrastructure speed.cloudflare.com itself uses. Home '
            'server ping (if shown) times a round trip to your PC over '
            'Tailscale separately, so a slow home connection doesn\'t get '
            'blamed on your internet, or vice versa.',
            style: TextStyle(color: Colors.white38, fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  String _phaseLabel(SpeedTestPhase phase) {
    switch (phase) {
      case SpeedTestPhase.idle:
        return 'Ready';
      case SpeedTestPhase.ping:
        return 'Measuring ping…';
      case SpeedTestPhase.download:
        return 'Measuring download…';
      case SpeedTestPhase.upload:
        return 'Measuring upload…';
      case SpeedTestPhase.done:
        return 'Done';
      case SpeedTestPhase.error:
        return 'Test failed';
    }
  }

  String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _NetworkTypeBanner extends StatelessWidget {
  final NetworkType? type;
  const _NetworkTypeBanner({required this.type});

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (type) {
      NetworkType.wifi => (Icons.wifi, 'Wi-Fi', Colors.greenAccent),
      NetworkType.cellular => (Icons.signal_cellular_alt, 'Cellular', Colors.orangeAccent),
      NetworkType.ethernet => (Icons.settings_ethernet, 'Ethernet', Colors.greenAccent),
      NetworkType.other => (Icons.device_unknown, 'Other connection', Colors.white54),
      NetworkType.offline => (Icons.wifi_off, 'Offline', Colors.redAccent),
      null => (Icons.hourglass_empty, 'Checking…', Colors.white38),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Text(
              'Connected via $label',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular readout in the middle of the screen. Shows the live number
/// for whichever phase is currently running, and freezes on the
/// download figure once the test is done (upload's final number is
/// still visible below in the metric rows either way).
class _SpeedDial extends StatelessWidget {
  final SpeedTestPhase phase;
  final SpeedTestResult result;
  final double? liveMbps;

  const _SpeedDial({
    required this.phase,
    required this.result,
    required this.liveMbps,
  });

  @override
  Widget build(BuildContext context) {
    String primary = '—';
    String unit = '';

    switch (phase) {
      case SpeedTestPhase.ping:
        primary = result.pingMs?.toStringAsFixed(0) ?? '···';
        unit = 'ms';
        break;
      case SpeedTestPhase.download:
      case SpeedTestPhase.upload:
        final v = liveMbps ?? (phase == SpeedTestPhase.download
            ? result.downloadMbps
            : result.uploadMbps);
        primary = v?.toStringAsFixed(1) ?? '···';
        unit = 'Mbps';
        break;
      case SpeedTestPhase.done:
        primary = result.downloadMbps?.toStringAsFixed(1) ?? '—';
        unit = 'Mbps ↓';
        break;
      case SpeedTestPhase.idle:
      case SpeedTestPhase.error:
        primary = '—';
        unit = '';
        break;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.22), width: 6),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              primary,
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (unit.isNotEmpty)
              Text(unit, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? sub;

  const _MetricRow({
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.white54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white70)),
                if (sub != null)
                  Text(sub!,
                      style: const TextStyle(color: Colors.white38, fontSize: 11.5)),
              ],
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
