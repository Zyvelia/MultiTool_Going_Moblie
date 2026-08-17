import 'dart:async';
import 'package:flutter/material.dart';
import '../models/mirrored_notification.dart';
import '../services/settings_service.dart';
import '../services/notifications_api_service.dart';
import '../services/local_notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _settingsService = SettingsService();
  NotificationsApiService? _api;

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _settings;
  List<MirroredNotification> _history = [];
  bool _connected = false;

  StreamSubscription<MirroredNotification>? _notifSub;
  StreamSubscription<bool>? _connSub;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final base = await _settingsService.baseUrl('notifications');
      if (base == null) throw Exception('Set your PC hostname in Settings first.');
      final api = NotificationsApiService(base);
      _api = api;

      final settings = await api.getSettings();
      final history = settings['history_enabled'] == true
          ? await api.getHistory()
          : <MirroredNotification>[];

      _notifSub = api.onNotification.listen((n) {
        if (!mounted) return;
        setState(() => _history = [n, ..._history]);
        LocalNotificationService.instance.showMirrored(n);
      });
      _connSub = api.onConnectionChange.listen((connected) {
        if (!mounted) return;
        setState(() => _connected = connected);
      });
      api.startStream();

      setState(() {
        _settings = settings;
        _history = history.reversed.toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _toggleEnabled(bool value) async {
    if (_api == null || _settings == null) return;
    setState(() => _settings!['enabled'] = value);
    try {
      await _api!.setEnabled(value);
    } catch (e) {
      setState(() => _settings!['enabled'] = !value);
      _showError('Failed to toggle mirroring: $e');
    }
  }

  Future<void> _toggleApp(String appName, bool value) async {
    if (_api == null || _settings == null) return;
    setState(() => _settings!['apps'][appName] = value);
    try {
      await _api!.setAppEnabled(appName, value);
    } catch (e) {
      setState(() => _settings!['apps'][appName] = !value);
      _showError('Failed to update $appName: $e');
    }
  }

  Future<void> _setPrivacyMode(String mode) async {
    if (_api == null || _settings == null) return;
    final previous = _settings!['privacy_mode'];
    setState(() => _settings!['privacy_mode'] = mode);
    try {
      await _api!.updateSettings({'privacy_mode': mode});
    } catch (e) {
      setState(() => _settings!['privacy_mode'] = previous);
      _showError('Failed to update privacy mode: $e');
    }
  }

  Future<void> _clearHistory() async {
    if (_api == null) return;
    try {
      await _api!.clearHistory();
      setState(() => _history = []);
    } catch (e) {
      _showError('Failed to clear history: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    final settings = _settings!;
    final enabled = settings['enabled'] == true;
    final apps = Map<String, dynamic>.from(settings['apps'] ?? {});
    final privacyMode = settings['privacy_mode'] as String? ?? 'hide_sensitive';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear history',
              onPressed: _clearHistory,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _connectionBanner(enabled),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Notification Mirroring'),
              subtitle: const Text('Mirror Windows notifications from this PC'),
              value: enabled,
              onChanged: _toggleEnabled,
            ),
            if (enabled) ...[
              const Divider(height: 32),
              Text('Applications', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              ...apps.entries.map((e) => CheckboxListTile(
                    title: Text(e.key),
                    value: e.value == true,
                    onChanged: (v) => _toggleApp(e.key, v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                  )),
              const Divider(height: 32),
              Text('Privacy', style: Theme.of(context).textTheme.titleMedium),
              RadioListTile<String>(
                title: const Text('Show full notification'),
                value: 'full',
                groupValue: privacyMode,
                onChanged: (v) => _setPrivacyMode(v!),
              ),
              RadioListTile<String>(
                title: const Text('Hide sensitive content'),
                subtitle: const Text('Auth codes, passwords, and similar stay masked'),
                value: 'hide_sensitive',
                groupValue: privacyMode,
                onChanged: (v) => _setPrivacyMode(v!),
              ),
              RadioListTile<String>(
                title: const Text('Show application only'),
                value: 'app_only',
                groupValue: privacyMode,
                onChanged: (v) => _setPrivacyMode(v!),
              ),
              const Divider(height: 32),
              Text('Today', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              if (_history.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No notifications yet.')),
                )
              else
                ..._history.map(_historyTile),
            ],
          ],
        ),
      ),
    );
  }

  Widget _connectionBanner(bool enabled) {
    final Color color;
    final String text;
    if (!enabled) {
      color = Colors.grey;
      text = '⚪ Connected — Notifications: OFF';
    } else if (_connected) {
      color = Colors.green;
      text = '🟢 Connected — Notifications: ON';
    } else {
      color = Colors.orange;
      text = '🟠 PC unreachable — will catch up when reconnected';
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _historyTile(MirroredNotification n) {
    return ListTile(
      leading: const Text('💬', style: TextStyle(fontSize: 20)),
      title: Text(n.appName, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [n.title, n.body].where((s) => s.isNotEmpty).join(': '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(_timeLabel(n.timestamp)),
    );
  }

  String _timeLabel(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }
}
