import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/stream_api_service.dart';
import '../services/user_facing_error.dart';
import '../services/wol_service.dart';
import '../theme/app_colors.dart';
import 'remote_desktop_screen.dart';

class StreamServiceScreen extends StatefulWidget {
  const StreamServiceScreen({super.key});

  @override
  State<StreamServiceScreen> createState() => _StreamServiceScreenState();
}

class _StreamServiceScreenState extends State<StreamServiceScreen> {
  final _settings = SettingsService();
  StreamApiService? _api;
  bool _online = false;
  bool _loading = true;
  String? _error;
  StreamStatus? _status;
  StreamCapabilities? _caps;
  StreamHealth? _health;
  final _macController = TextEditingController();
  final _broadcastController = TextEditingController(text: '255.255.255.255');
  bool _waking = false;
  bool _wakeConnecting = false;
  String? _wakeStatus;
  String? _busyAction;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _macController.dispose();
    _broadcastController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final base = await _settings.baseUrl('stream');
    final code = await _settings.getAccessCode('stream');
    final mac = await _settings.getWolMac();
    final broadcast = await _settings.getWolBroadcast();
    _macController.text = mac ?? '';
    _broadcastController.text = broadcast ?? '255.255.255.255';
    if (base != null) {
      _api = StreamApiService(base, accessCode: code);
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (_api == null) {
      setState(() {
        _loading = false;
        _online = false;
        _error = 'Set your Tailscale hostname in Settings first.';
      });
      return;
    }
    try {
      final online = await _api!.checkStatus();
      if (!online) {
        setState(() {
          _loading = false;
          _online = false;
          _status = null;
          _caps = null;
          _health = null;
        });
        return;
      }
      final health = await _api!.fetchHealth();
      final status = await _api!.fetchStatus();
      final caps = await _api!.fetchCapabilities();
      final wol = await _api!.fetchWolConfig();
      if (wol.macAddress.isNotEmpty) {
        _macController.text = wol.macAddress;
        await _settings.setWolMac(wol.macAddress);
      }
      if (wol.broadcast.isNotEmpty) {
        _broadcastController.text = wol.broadcast;
        await _settings.setWolBroadcast(wol.broadcast);
      }
      setState(() {
        _online = true;
        _status = status;
        _caps = caps;
        _health = health;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _online = false;
        _error = explainError(e);
      });
    }
  }

  Future<void> _saveWolLocally() async {
    await _settings.setWolMac(_macController.text.trim());
    await _settings.setWolBroadcast(_broadcastController.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Wake settings saved on this phone')),
    );
  }

  Future<void> _openRemoteDesktop() async {
    if (_api == null || _caps == null || !_caps!.remoteScreen) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RemoteDesktopScreen(
          api: _api!,
          fps: _caps!.remoteFps,
          inputEnabled: _caps!.remoteInput,
          useWebRtc: _caps!.remoteWebrtc,
        ),
      ),
    );
  }

  Future<void> _wakeAndConnect({bool openRemote = false}) async {
    final mac = _macController.text.trim();
    if (mac.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the PC MAC address first.')),
      );
      return;
    }
    if (_api == null) return;
    setState(() {
      _waking = true;
      _wakeConnecting = true;
      _wakeStatus = 'Sending wake packet…';
    });
    try {
      await WolService.send(
        macAddress: mac,
        broadcast: _broadcastController.text.trim().isEmpty
            ? '255.255.255.255'
            : _broadcastController.text.trim(),
      );
      await _saveWolLocally();
      if (!mounted) return;
      setState(() => _wakeStatus = 'Waiting for PC on Tailscale…');
      final up = await _api!.waitUntilOnline();
      if (!mounted) return;
      if (!up) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'PC did not come online in time. Check WoL, power, and that Stream Service auto-starts on the PC.',
            ),
          ),
        );
        return;
      }
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PC is online.')),
      );
      if (openRemote && _online && _caps?.remoteScreen == true) {
        await _openRemoteDesktop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(explainError(e))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _waking = false;
          _wakeConnecting = false;
          _wakeStatus = null;
        });
      }
    }
  }

  Future<void> _wakePc() async {
    final mac = _macController.text.trim();
    if (mac.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the PC MAC address (or open the PC while online to sync it).')),
      );
      return;
    }
    setState(() => _waking = true);
    try {
      await WolService.send(
        macAddress: mac,
        broadcast: _broadcastController.text.trim().isEmpty
            ? '255.255.255.255'
            : _broadcastController.text.trim(),
      );
      await _saveWolLocally();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wake packet sent — PC should power on if WoL is enabled.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(explainError(e))),
      );
    } finally {
      if (mounted) setState(() => _waking = false);
    }
  }

  Future<void> _power(String action, String label) async {
    if (_api == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: Text('Run "$label" on ${_status?.hostname ?? 'this PC'}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyAction = action);
    try {
      await _api!.power(action);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label sent')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(explainError(e))),
      );
    } finally {
      if (mounted) setState(() => _busyAction = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PC control'),
        actions: [
          IconButton(onPressed: _loading ? null : _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: AppColors.accent)),
                _StatusCard(online: _online, status: _status, health: _health),
                if (_wakeStatus != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_wakeStatus!, style: const TextStyle(color: AppColors.muted)),
                  ),
                const SizedBox(height: 16),
                Text('Wake PC (same Wi‑Fi / LAN)', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _macController,
                  decoration: const InputDecoration(
                    labelText: 'PC MAC address',
                    hintText: 'aa:bb:cc:dd:ee:ff',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _broadcastController,
                  decoration: const InputDecoration(
                    labelText: 'Broadcast address',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _waking ? null : _wakePc,
                  icon: _waking && !_wakeConnecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.power_settings_new),
                  label: const Text('Send wake packet'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _wakeConnecting ? null : () => _wakeAndConnect(openRemote: false),
                  icon: _wakeConnecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_sync),
                  label: const Text('Wake & wait for PC online'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _wakeConnecting ? null : () => _wakeAndConnect(openRemote: true),
                  icon: const Icon(Icons.desktop_windows),
                  label: const Text('Wake & open remote desktop'),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: _saveWolLocally, child: const Text('Save wake settings on phone')),
                const SizedBox(height: 24),
                Text('While PC is online (Tailscale)', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (!_online)
                  const Text(
                    'Power buttons need the PC awake and Stream Service live (Remote Hub → Go Live).',
                    style: TextStyle(color: AppColors.muted),
                  ),
                if (_online && _caps != null && _caps!.remoteScreen) ...[
                  FilledButton.icon(
                    onPressed: _api == null ? null : _openRemoteDesktop,
                    icon: const Icon(Icons.desktop_windows),
                    label: const Text('Open remote desktop'),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_online && _caps != null) ...[
                  _PowerButton(
                    label: 'Lock',
                    icon: Icons.lock,
                    enabled: _caps!.lock && _busyAction == null,
                    loading: _busyAction == 'lock',
                    onPressed: () => _power('lock', 'Lock'),
                  ),
                  _PowerButton(
                    label: 'Sleep',
                    icon: Icons.bedtime_outlined,
                    enabled: _caps!.sleep && _busyAction == null,
                    loading: _busyAction == 'sleep',
                    onPressed: () => _power('sleep', 'Sleep'),
                  ),
                  _PowerButton(
                    label: 'Shutdown',
                    icon: Icons.power_off,
                    enabled: _caps!.shutdown && _busyAction == null,
                    loading: _busyAction == 'shutdown',
                    onPressed: () => _power('shutdown', 'Shutdown'),
                  ),
                  _PowerButton(
                    label: 'Restart',
                    icon: Icons.restart_alt,
                    enabled: _caps!.restart && _busyAction == null,
                    loading: _busyAction == 'restart',
                    onPressed: () => _power('restart', 'Restart'),
                  ),
                ],
              ],
            ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final bool online;
  final StreamStatus? status;
  final StreamHealth? health;

  const _StatusCard({required this.online, this.status, this.health});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              online ? Icons.cloud_done : Icons.cloud_off,
              color: online ? AppColors.accentGlow : AppColors.muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(online ? 'PC reachable' : 'PC offline (Tailscale)'),
                  if (status != null)
                    Text(
                      '${status!.hostname} · WoL ${status!.wolConfigured ? 'configured' : 'not set on PC'}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  if (online && health != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Screen ${health!.screenStream ? 'on' : 'off'} · '
                      'Input ${health!.remoteInput ? 'on' : 'off'} · '
                      'WebRTC ${health!.webrtcAvailable ? (health!.webrtcActive ? 'live' : 'ready') : 'unavailable'}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                    if (health!.webrtcError != null)
                      Text(
                        health!.webrtcError!,
                        style: const TextStyle(color: AppColors.accent, fontSize: 11),
                      ),
                  ],
                  if (!online)
                    const Text(
                      'Tailscale / Stream Service not reachable — wake the PC or start remote on the desktop.',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final bool loading;
  final VoidCallback onPressed;

  const _PowerButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: loading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon),
        label: Text(label),
      ),
    );
  }
}
