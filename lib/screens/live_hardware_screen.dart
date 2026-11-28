import 'dart:async';
import 'package:flutter/material.dart';
import '../services/live_server_client.dart';

/// Read-only aggregate telemetry from the paired C# desktop. No process
/// actions, device identifiers or arbitrary hardware queries are available.
class LiveHardwareScreen extends StatefulWidget {
  const LiveHardwareScreen({super.key, required this.client});
  final LiveServerClient client;
  @override
  State<LiveHardwareScreen> createState() => _LiveHardwareScreenState();
}

class _LiveHardwareScreenState extends State<LiveHardwareScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _sample;
  final _cpu = <double?>[], _ram = <double?>[];
  Timer? _timer;
  bool _busy = false, _foreground = true;
  String? _error, _lastSample;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule(Duration.zero);
  }

  void _schedule([Duration delay = const Duration(seconds: 3)]) {
    _timer?.cancel();
    if (mounted && _foreground) {
      _timer = Timer(delay, () => unawaited(_refresh()));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      ++_generation;
      _timer?.cancel();
      setState(() { _sample = null; _cpu.clear(); _ram.clear(); _lastSample = null; });
    } else {
      _schedule(Duration.zero);
    }
  }

  static double? _number(Object? value) =>
      value is num && value.isFinite && value >= 0 ? value.toDouble() : null;
  static double? _percent(Object? value) {
    final n = _number(value);
    return n != null && n <= 100 ? n : null;
  }

  Future<void> _refresh() async {
    if (!mounted || !_foreground) return;
    if (_busy) { _schedule(); return; }
    final generation = _generation;
    setState(() => _busy = true);
    try {
      final data = await widget.client.hardware();
      if (!mounted || !_foreground || generation != _generation) return;
      if (data['sampled_at'] is! String || data['drives'] is! List || data['gpus'] is! List) {
        throw const LiveServerException('Unexpected hardware response.');
      }
      setState(() {
        _sample = data; _error = null;
        if (_lastSample != data['sampled_at']) {
          _lastSample = data['sampled_at'] as String;
          _cpu.add(_percent(data['cpu'])); _ram.add(_percent(data['ram']));
          if (_cpu.length > 60) { _cpu.removeAt(0); _ram.removeAt(0); }
        }
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _sample = null; _cpu.clear(); _ram.clear(); _lastSample = null;
          _error = e is LiveServerException
              ? e.message
              : 'Unable to reach the PC. Check Tailscale and Live Server.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _schedule(_error == null ? const Duration(seconds: 3) : const Duration(seconds: 8));
      }
    }
  }

  @override
  void dispose() {
    ++_generation; _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _bytes(Object? n) {
    final number = _number(n);
    if (number == null) return 'Unavailable';
    var value = number;
    var unit = 0;
    const labels = ['B','KiB','MiB','GiB','TiB','PiB'];
    while (value >= 1024 && unit < labels.length - 1) { value /= 1024; unit++; }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${labels[unit]}';
  }
  String _rate(Object? n) => _number(n) == null ? 'Unavailable' : '${_bytes(n)}/s';
  Widget _metric(String label, Object? raw, List<double?> history, {String? detail}) {
    final percent = _percent(raw);
    final color = Theme.of(context).colorScheme.primary;
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
          Text(percent == null ? 'Unavailable' : '${percent.toStringAsFixed(1)}%',
            style: Theme.of(context).textTheme.headlineSmall),
        ]),
        if (detail != null) Text(detail),
        const SizedBox(height: 12),
        if (percent != null) LinearProgressIndicator(value: percent / 100),
        if (history.length > 1) ...[
          const SizedBox(height: 12),
          SizedBox(height: 64, width: double.infinity, child: CustomPaint(
            painter: _HistoryPainter(List<double?>.of(history), color))),
          const Text('Recent readings · up to 3 minutes'),
        ],
      ])));
  }

  @override
  Widget build(BuildContext context) {
    final data = _sample;
    return Scaffold(
      appBar: AppBar(title: const Text('Live System Monitor'), actions: [
        IconButton(tooltip: 'Refresh readings', onPressed: _busy ? null : () => _schedule(Duration.zero),
          icon: const Icon(Icons.refresh)),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('PC hardware', style: Theme.of(context).textTheme.headlineSmall),
        const Text('Read-only · Private Tailscale connection'),
        const SizedBox(height: 12),
        if (data == null) ...[
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          const Text('Pair this phone, grant hardware read permission, and enable aggregate system monitor sharing on PC.'),
        ] else ...[
          Text('Sample: ${DateTime.tryParse(data['sampled_at'] as String)?.toLocal().toString() ?? 'Unavailable'}'),
          _metric('CPU usage', data['cpu'], _cpu),
          _metric('Memory usage', data['ram'], _ram,
            detail: '${_bytes(data['ram_used'])} / ${_bytes(data['ram_total'])}'),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Network totals', style: Theme.of(context).textTheme.titleMedium),
              ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.download),
                title: const Text('Receive'), trailing: Text(_rate(data['receive']))),
              ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.upload),
                title: const Text('Send'), trailing: Text(_rate(data['send']))),
              const Text('Aggregate adapter counters; includes virtual adapters.'),
            ]))),
          Text('Storage', style: Theme.of(context).textTheme.titleLarge),
          if ((data['drives'] as List).isEmpty) const Text('No fixed-drive readings.'),
          for (final drive in (data['drives'] as List).whereType<Map>().take(32))
            _metric('Drive ${drive['name'] ?? '?'}',
              _number(drive['total']) != null && _number(drive['total'])! > 0 &&
              _number(drive['free']) != null && _number(drive['free'])! <= _number(drive['total'])!
                ? 100 * (1 - _number(drive['free'])! / _number(drive['total'])!) : null,
              const [], detail: '${_bytes(drive['free'])} free / ${_bytes(drive['total'])} total'),
          Text('GPU', style: Theme.of(context).textTheme.titleLarge),
          Text('${data['gpu_status'] ?? 'Unavailable'}'),
          for (final gpu in (data['gpus'] as List).whereType<Map>().take(16))
            _metric('${gpu['name'] ?? 'GPU'}', gpu['usage'], const [],
              detail: 'Temperature: ${_number(gpu['temperature'])?.toStringAsFixed(1) ?? 'Unavailable'} °C\n'
                'VRAM: ${_number(gpu['used_mib'])?.toStringAsFixed(0) ?? 'Unavailable'} / '
                '${_number(gpu['total_mib'])?.toStringAsFixed(0) ?? 'Unavailable'} MiB'),
        ],
      ]),
    );
  }
}

class _HistoryPainter extends CustomPainter {
  const _HistoryPainter(this.points, this.color);
  final List<double?> points;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = color.withValues(alpha: .15)..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (points.length < 2) return;
    final line = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2;
    final path = Path();
    var started = false;
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      if (point == null) { started = false; continue; }
      final x = size.width * i / (points.length - 1);
      final y = size.height * (1 - point / 100);
      if (started) { path.lineTo(x, y); } else { path.moveTo(x, y); started = true; }
    }
    canvas.drawPath(path, line);
  }
  @override
  bool shouldRepaint(covariant _HistoryPainter oldDelegate) => true;
}
