import 'package:flutter/material.dart';

import '../services/dashboard_service.dart';
import '../theme/appearance.dart';

class DashboardStatus extends StatefulWidget {
  const DashboardStatus({
    super.key, required this.load, required this.active,
    required this.onRemote, required this.onMusic, required this.onSend,
    required this.onSettings,
  });

  final Future<DashboardSnapshot> Function() load;
  final bool active;
  final VoidCallback onRemote, onMusic, onSend, onSettings;

  @override
  State<DashboardStatus> createState() => _DashboardStatusState();
}

class _DashboardStatusState extends State<DashboardStatus> with WidgetsBindingObserver {
  DashboardSnapshot? _snapshot;
  bool _loading = false;
  bool _failed = false;
  bool _refreshAfterLoad = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) _refresh();
  }

  @override
  void didUpdateWidget(covariant DashboardStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.active && state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) {
      _refreshAfterLoad = true;
      return;
    }
    setState(() { _loading = true; _failed = false; });
    try {
      final result = await widget.load();
      if (mounted) setState(() => _snapshot = result);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_refreshAfterLoad) {
          _refreshAfterLoad = false;
          if (widget.active) _refresh();
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _size(int? bytes) {
    if (bytes == null) return '—';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final p = Appearance.of(context);
    final snap = _snapshot;
    final color = switch (snap?.reachability) {
      DashboardReachability.reachable => const Color(0xFF32E6A1),
      DashboardReachability.offline || DashboardReachability.unavailable || DashboardReachability.denied => const Color(0xFFFFB568),
      _ => p.accentGlow,
    };
    final checked = snap == null ? null : TimeOfDay.fromDateTime(snap.checkedAt).format(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.card, borderRadius: BorderRadius.circular(19),
          border: Border.all(color: p.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.sensors_rounded, color: color),
            const SizedBox(width: 9),
            Expanded(child: Text('Connection', style: TextStyle(color: p.onSurface, fontWeight: FontWeight.w700, fontSize: 17))),
            IconButton(
              tooltip: 'Refresh dashboard',
              onPressed: _loading ? null : _refresh,
              icon: _loading
                  ? const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.refresh_rounded, color: p.accentGlow),
            ),
          ]),
          Text(_failed ? 'Refresh failed — previous reading may be stale' : snap?.connectionLabel ?? 'Checking connection…',
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text([
            snap?.networkLabel ?? 'Network unknown',
            switch (snap?.paired) { true => 'Paired locally', false => 'Not paired', null => 'Pairing unknown' },
            if (snap?.latencyMs != null) '${snap!.latencyMs} ms HTTP response',
          ].join(' · '), style: TextStyle(color: p.muted, fontSize: 12)),
          if (checked != null)
            Text('Last checked: $checked', style: TextStyle(color: p.muted, fontSize: 11)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(onPressed: widget.onRemote, icon: const Icon(Icons.computer_rounded), label: const Text('PC Remote')),
            OutlinedButton(onPressed: widget.onSettings, child: const Text('Connection settings')),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      Text('QUICK ACTIONS', style: TextStyle(color: p.muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _Action(icon: Icons.library_music_rounded, title: 'Music', onTap: widget.onMusic)),
        const SizedBox(width: 8),
        Expanded(child: _Action(icon: Icons.send_rounded, title: 'Quick Send', onTap: widget.onSend)),
      ]),
      const SizedBox(height: 12),
      Text('LOCAL LIBRARY', style: TextStyle(color: p.muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _Metric(label: 'Indexed tracks', value: snap?.indexed?.toString() ?? '—'),
        _Metric(label: 'Downloaded', value: snap?.downloaded?.toString() ?? '—'),
        _Metric(label: 'Cache size', value: _size(snap?.downloadBytes)),
      ]),
    ]);
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.title, required this.onTap});
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Appearance.of(context);
    return Material(
      color: p.card, borderRadius: BorderRadius.circular(14), clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Icon(icon, color: p.accentGlow), const SizedBox(width: 8),
            Expanded(child: Text(title, style: TextStyle(color: p.onSurface, fontWeight: FontWeight.w600))),
          ]),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final p = Appearance.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(color: p.accentGlow, fontSize: 19, fontWeight: FontWeight.w700)),
        Text(label, style: TextStyle(color: p.muted, fontSize: 11)),
      ]),
    );
  }
}
