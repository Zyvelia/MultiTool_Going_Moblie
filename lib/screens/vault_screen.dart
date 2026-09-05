import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../models/vault_entry.dart';
import '../services/screen_security_service.dart';
import '../services/settings_service.dart';
import '../services/user_facing_error.dart';
import '../services/vault_api_service.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _settings = SettingsService();
  final _passwordController = TextEditingController();
  VaultApiService? _api;
  String? _token;
  String? _error;
  bool _loading = false;

  List<VaultEntry> _entries = [];
  List<TotpCode> _codes = [];
  Timer? _totpTimer;
  int _secondsRemaining = 30;

  /// Codes stay masked until explicitly revealed, so the list is safe to have
  /// open in public. Keyed by entry id and dropped again on a timer.
  final Set<String> _revealedIds = {};
  final Map<String, Timer> _revealTimers = {};
  static const _revealDuration = Duration(seconds: 15);

  Timer? _idleTimer;
  DateTime? _backgroundedAt;
  Timer? _clipboardTimer;
  String? _clipboardValue;

  /// Short enough to matter, long enough to switch apps and paste a code.
  static const _backgroundLockAfter = Duration(seconds: 30);
  static const _idleLockAfter = Duration(minutes: 3);
  static const _clipboardClearAfter = Duration(seconds: 30);

  final _screenSecurity = ScreenSecurityService.instance;
  StreamSubscription<void>? _screenshotSub;
  StreamSubscription<bool>? _captureSub;
  bool _screenCaptured = false;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    _initScreenSecurity();
    _init();
  }

  Future<void> _initScreenSecurity() async {
    await _screenSecurity.protect();
    _screenshotSub = _screenSecurity.onScreenshot.listen((_) {
      // iOS cannot block the capture, so the least-bad response is to drop the
      // codes and tell the user the shot they just took contains one.
      if (!mounted) return;
      setState(_hideAllCodes);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Screenshot detected — codes hidden'),
          duration: Duration(seconds: 3),
        ),
      );
    });
    _captureSub = _screenSecurity.onCaptureChanged.listen((captured) {
      if (!mounted) return;
      setState(() {
        _screenCaptured = captured;
        if (captured) _hideAllCodes();
      });
    });
    final captured = await _screenSecurity.isCaptured();
    if (mounted && captured) setState(() => _screenCaptured = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_token == null) return;
    switch (state) {
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since != null &&
            DateTime.now().difference(since) >= _backgroundLockAfter) {
          _lock();
          return;
        }
        _startTotpRefresh();
        _resetIdleTimer();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // Codes must never sit revealed behind the app switcher, and there is
        // no reason to keep polling fresh ones while nobody is looking.
        _backgroundedAt ??= DateTime.now();
        _totpTimer?.cancel();
        _idleTimer?.cancel();
        if (_revealedIds.isNotEmpty && mounted) {
          setState(_hideAllCodes);
        } else {
          _hideAllCodes();
        }
    }
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (_token == null) return;
    _idleTimer = Timer(_idleLockAfter, _lock);
  }

  Future<void> _lock() async {
    if (_token == null) return;
    await _logout();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Vault locked'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _init() async {
    final base = await _settings.baseUrl('vault');
    if (base != null) {
      setState(() => _api = VaultApiService(base));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _screenshotSub?.cancel();
    _captureSub?.cancel();
    // Leaving FLAG_SECURE set would make the rest of the app unscreenshottable.
    _screenSecurity.unprotect();
    _totpTimer?.cancel();
    _idleTimer?.cancel();
    _clipboardTimer?.cancel();
    _hideAllCodes();
    _tabController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_api == null) return;
    final password = _passwordController.text;
    if (password.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await _api!.login(password);
      final entries = await _api!.fetchEntries(token);
      final codes = await _api!.fetchTotpCodes(token);
      setState(() {
        _token = token;
        _entries = entries;
        _codes = codes;
        _loading = false;
        _passwordController.clear();
      });
      _startTotpRefresh();
      _resetIdleTimer();
    } catch (e) {
      setState(() {
        _error = explainError(e, doing: 'unlock the vault');
        _loading = false;
      });
    }
  }

  void _startTotpRefresh() {
    _totpTimer?.cancel();
    _totpTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_token == null || _api == null) return;
      setState(() {
        _secondsRemaining = _secondsRemaining <= 0 ? 30 : _secondsRemaining - 1;
      });
      if (_secondsRemaining <= 1) {
        try {
          final codes = await _api!.fetchTotpCodes(_token!);
          if (mounted) setState(() => _codes = codes);
        } catch (_) {
          // transient network hiccup — keep showing the last known codes
        }
      }
    });
  }

  Future<void> _logout() async {
    if (_token != null && _api != null) {
      await _api!.logout(_token!);
    }
    _totpTimer?.cancel();
    setState(() {
      _token = null;
      _entries = [];
      _codes = [];
      _hideAllCodes();
    });
  }

  void _toggleReveal(String id) {
    if (!_revealedIds.contains(id) && _screenCaptured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Screen is being recorded — stop recording to view codes'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    setState(() {
      if (_revealedIds.remove(id)) {
        _revealTimers.remove(id)?.cancel();
        return;
      }
      _revealedIds.add(id);
    });
    _revealTimers[id]?.cancel();
    _revealTimers[id] = Timer(_revealDuration, () {
      if (!mounted) return;
      setState(() => _revealedIds.remove(id));
      _revealTimers.remove(id);
    });
  }

  void _hideAllCodes() {
    for (final t in _revealTimers.values) {
      t.cancel();
    }
    _revealTimers.clear();
    _revealedIds.clear();
  }

  void _copyToClipboard(String text, {bool autoClear = false}) {
    Clipboard.setData(ClipboardData(text: text));
    _resetIdleTimer();
    if (autoClear) _scheduleClipboardClear(text);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(autoClear
            ? 'Copied — clears in ${_clipboardClearAfter.inSeconds}s'
            : 'Copied'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _scheduleClipboardClear(String value) {
    _clipboardTimer?.cancel();
    _clipboardValue = value;
    _clipboardTimer = Timer(_clipboardClearAfter, () async {
      final expected = _clipboardValue;
      _clipboardValue = null;
      if (expected == null) return;
      // Only wipe our own code; the user may have copied something else since.
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text != expected) return;
      await Clipboard.setData(const ClipboardData(text: ''));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_api == null) {
      return const Scaffold(
        body: Center(
          child: Text('Set your PC hostname in Settings first.',
              style: TextStyle(color: Colors.white54)),
        ),
      );
    }

    if (_token == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Security Vault')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.lock, size: 48, color: Colors.white38),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                onSubmitted: (_) => _login(),
                decoration: const InputDecoration(
                  labelText: 'Master password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.redAccent)),
                ),
              FilledButton(
                onPressed: _loading ? null : _login,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(_loading ? 'Unlocking…' : 'Unlock'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Security Vault'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Passwords'),
            Tab(text: 'Authenticator'),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.lock_open), onPressed: _logout),
        ],
      ),
      // Any touch counts as activity, so the idle lock only fires when the
      // vault is genuinely sitting unattended.
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _resetIdleTimer(),
        child: Column(
          children: [
            if (_screenCaptured)
              Container(
                width: double.infinity,
                color: Colors.red.withValues(alpha: 0.85),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: const Row(
                  children: [
                    Icon(Icons.videocam, size: 16, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Screen is being recorded or mirrored',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildEntries(),
                  _buildTotp(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntries() {
    if (_entries.isEmpty) {
      return const Center(
        child: Text('No entries.', style: TextStyle(color: Colors.white54)),
      );
    }
    return ListView.builder(
      itemCount: _entries.length,
      itemBuilder: (context, i) {
        final e = _entries[i];
        return ListTile(
          leading: Icon(
            e.favorite ? Icons.star : Icons.language,
            color: e.favorite ? Colors.amber : Colors.white38,
          ),
          title: Text(e.site),
          subtitle: Text(e.username),
          trailing: IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Copy password',
            onPressed: () => _copyToClipboard(e.password, autoClear: true),
          ),
        );
      },
    );
  }

  Widget _buildTotp() {
    if (_codes.isEmpty) {
      return const Center(
        child: Text('No authenticator codes.',
            style: TextStyle(color: Colors.white54)),
      );
    }
    return ListView.builder(
      itemCount: _codes.length,
      itemBuilder: (context, i) {
        final c = _codes[i];
        final revealed = _revealedIds.contains(c.id);
        return ListTile(
          leading: const Icon(Icons.shield_outlined, color: Colors.white38),
          title: Text(c.issuer.isNotEmpty ? c.issuer : c.name),
          subtitle: Text(c.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                // Mask to the real length so a glance never leaks the digits.
                revealed ? c.code : '•' * (c.code.isEmpty ? 6 : c.code.length),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: revealed ? 0 : 2,
                  color: revealed ? AppColors.accent : Colors.white38,
                ),
              ),
              IconButton(
                icon: Icon(
                  revealed ? Icons.visibility_off : Icons.visibility,
                  size: 20,
                  color: Colors.white54,
                ),
                tooltip: revealed ? 'Hide code' : 'Show code',
                onPressed: () => _toggleReveal(c.id),
              ),
            ],
          ),
          onTap: () => _copyToClipboard(c.code, autoClear: true),
        );
      },
    );
  }
}
