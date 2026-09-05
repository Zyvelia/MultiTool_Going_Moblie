import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../models/clipboard_entry.dart';
import '../services/settings_service.dart';
import '../services/clipboard_api_service.dart';
import '../services/clipboard_cache_service.dart';
import '../services/connectivity_service.dart';
import '../services/user_facing_error.dart';

class ClipboardScreen extends StatefulWidget {
  const ClipboardScreen({super.key});

  @override
  State<ClipboardScreen> createState() => _ClipboardScreenState();
}

class _ClipboardScreenState extends State<ClipboardScreen> {
  final _settings = SettingsService();
  final _cache = ClipboardCacheService.instance;
  ClipboardApiService? _api;
  List<ClipboardEntry> _entries = [];
  bool _loading = true;
  String _query = '';

  StreamSubscription<NetworkType>? _connectivitySub;
  NetworkType _networkType = NetworkType.other;
  // True once a live fetch has actually failed — distinct from
  // _networkType == offline, which only means "no interface at all" and
  // misses the more common case here (interface up, Tailscale hostname
  // unreachable). Mirrors NotesScreen's own _unreachable flag.
  bool _unreachable = false;

  @override
  void initState() {
    super.initState();
    _init();
    _initConnectivity();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    await _cache.ensureReady();
    _refreshLocal();
    final base = await _settings.baseUrl('clipboard');
    if (base == null) return;
    setState(() => _api = ClipboardApiService(base));
    await _load();
  }

  void _initConnectivity() {
    ConnectivityService.instance.current().then((t) {
      if (mounted) setState(() => _networkType = t);
    });
    _connectivitySub = ConnectivityService.instance.onChange.listen((type) async {
      final wasOffline = _networkType == NetworkType.offline;
      if (mounted) setState(() => _networkType = type);
      if (type == NetworkType.offline) return;
      if (!wasOffline) return; // only act on offline -> back-online edges
      await _load();
    });
  }

  void _refreshLocal() {
    setState(() {
      _entries = _cache.localEntries(query: _query);
      _loading = false;
    });
  }

  /// Shows the cached list immediately (works with no connection at
  /// all), then — if a server is configured — tries to pull the latest
  /// from the desktop.
  Future<void> _load() async {
    _refreshLocal();
    if (_api == null) return;
    try {
      final serverEntries = await _api!.fetchEntries();
      await _cache.replaceFromServer(serverEntries);
      if (mounted) setState(() => _unreachable = false);
      _refreshLocal();
    } catch (_) {
      // Desktop unreachable — cached list (already shown) is the
      // fallback.
      if (mounted) setState(() => _unreachable = true);
    }
  }

  void _onSearchChanged(String value) {
    // Filters the local cache directly — no network round trip, so
    // search works the same online or off.
    setState(() {
      _query = value;
      _entries = _cache.localEntries(query: _query);
    });
  }

  Future<void> _copy(ClipboardEntry entry) async {
    await Clipboard.setData(ClipboardData(text: entry.text));
    _showToast('Copied to phone clipboard');
  }

  Future<void> _togglePin(ClipboardEntry entry) async {
    if (_api == null || _networkType == NetworkType.offline) {
      _showToast('Connect to the desktop to toggle pin');
      return;
    }
    try {
      await _api!.togglePin(entry.id);
      await _load();
    } catch (e) {
      _showToast(explainError(e));
    }
  }

  Future<void> _delete(ClipboardEntry entry) async {
    if (_api == null || _networkType == NetworkType.offline) {
      _showToast('Connect to the desktop to delete');
      return;
    }
    try {
      await _api!.deleteEntry(entry.id);
      await _load();
    } catch (e) {
      _showToast(explainError(e));
    }
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  String _fmtTime(double ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch((ts * 1000).round());
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    if (_api == null && !_loading && _entries.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Set your PC hostname in Settings first.',
                style: TextStyle(color: Colors.white54),
                textAlign: TextAlign.center),
          ),
        ),
      );
    }

    final showOfflineBanner =
        _networkType == NetworkType.offline || _unreachable;

    return Scaffold(
      appBar: AppBar(
        title: Text(_entries.isNotEmpty
            ? '${_entries.length} clipboard item${_entries.length == 1 ? '' : 's'}'
            : 'Clipboard'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Column(
          children: [
            if (showOfflineBanner)
              Container(
                width: double.infinity,
                color: Colors.amber.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: const Text(
                  'Offline — showing history saved on this phone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.amber),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search history…',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _entries.isEmpty
                      ? ListView(
                          children: const [
                            Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Nothing here yet — copy something on the PC.',
                                style: TextStyle(color: Colors.white54),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: _entries.length,
                          itemBuilder: (context, i) {
                            final entry = _entries[i];
                            return ListTile(
                              leading: Icon(
                                entry.pinned
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                                color: entry.pinned
                                    ? AppColors.accent
                                    : Colors.white38,
                              ),
                              title: Text(
                                entry.text,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                _fmtTime(entry.timestamp),
                                style: const TextStyle(color: Colors.white54),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 20),
                                    tooltip: 'Copy to phone',
                                    onPressed: () => _copy(entry),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 20),
                                    onPressed: () => _delete(entry),
                                  ),
                                ],
                              ),
                              onTap: () => _copy(entry),
                              onLongPress: () => _togglePin(entry),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
