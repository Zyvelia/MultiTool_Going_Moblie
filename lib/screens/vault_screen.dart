import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import 'home_leading.dart';
import '../models/vault_entry.dart';
import '../services/settings_service.dart';
import '../services/user_facing_error.dart';
import '../services/vault_api_service.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> with WidgetsBindingObserver {
  final _settings = SettingsService();
  final _passwordController = TextEditingController();
  final _searchController = TextEditingController();
  VaultApiService? _api;
  String? _token;
  String? _error;
  bool _loading = false;
  String _query = '';

  /// One open row. Null means every login is collapsed.
  String? _openKey;

  List<VaultEntry> _entries = [];
  List<TotpCode> _codes = [];
  Timer? _totpTimer;
  int _secondsRemaining = 30;
  int _period = 30;

  /// Codes stay masked until explicitly revealed, so the list is safe to have
  /// open in public. The value is when the reveal ends.
  final Map<String, DateTime> _revealUntil = {};
  static const _revealDuration = Duration(seconds: 15);

  Timer? _idleTimer;
  DateTime? _backgroundedAt;
  Timer? _clipboardTimer;
  String? _clipboardValue;

  /// Short enough to matter, long enough to switch apps and paste a code.
  static const _backgroundLockAfter = Duration(seconds: 30);
  static const _idleLockAfter = Duration(minutes: 3);
  static const _clipboardClearAfter = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
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
        if (_revealUntil.isNotEmpty && mounted) {
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
    _totpTimer?.cancel();
    _idleTimer?.cancel();
    _clipboardTimer?.cancel();
    _hideAllCodes();
    _passwordController.dispose();
    _searchController.dispose();
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
      final feed = await _api!.fetchTotpCodes(token);
      setState(() {
        _token = token;
        _entries = entries;
        _applyFeed(feed);
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

  void _applyFeed(TotpFeed feed) {
    _codes = feed.codes;
    _period = feed.period;
    _secondsRemaining = feed.secondsRemaining.clamp(0, feed.period);
  }

  void _startTotpRefresh() {
    _totpTimer?.cancel();
    _totpTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_token == null || _api == null || !mounted) return;
      final now = DateTime.now();
      final remaining = _secondsRemaining - 1;
      setState(() {
        _revealUntil.removeWhere((_, until) => !now.isBefore(until));
        _secondsRemaining = remaining < 0 ? 0 : remaining;
      });
      if (remaining > 0) return;
      try {
        final feed = await _api!.fetchTotpCodes(_token!);
        if (mounted) setState(() => _applyFeed(feed));
      } catch (_) {
        // transient network hiccup — keep showing the last known codes
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
      _openKey = null;
      _query = '';
      _searchController.clear();
      _hideAllCodes();
    });
  }

  void _toggleReveal(String id) {
    setState(() {
      if (_revealUntil.containsKey(id)) {
        _revealUntil.remove(id);
        return;
      }
      _revealUntil[id] = DateTime.now().add(_revealDuration);
    });
  }

  bool _isRevealed(String id) {
    final until = _revealUntil[id];
    return until != null && DateTime.now().isBefore(until);
  }

  int _revealSecondsLeft(String id) {
    final until = _revealUntil[id];
    if (until == null) return 0;
    final left = until.difference(DateTime.now()).inSeconds;
    return left < 0 ? 0 : left;
  }

  void _hideAllCodes() {
    _revealUntil.clear();
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
      return Scaffold(
        appBar: AppBar(
          leading: homeBackLeading(context),
          title: const Text('Security Vault'),
        ),
        body: const Center(
          child: Text('Set your PC hostname in Settings first.',
              style: TextStyle(color: Colors.white54)),
        ),
      );
    }

    if (_token == null) {
      return Scaffold(
        appBar: AppBar(
          leading: homeBackLeading(context),
          title: const Text('Security Vault'),
        ),
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

    final rows = _visibleRows();
    return Scaffold(
      appBar: AppBar(
        leading: homeBackLeading(context),
        title: const Text('Security Vault'),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search sites',
                  prefixIcon: const Icon(Icons.search, color: Colors.white38),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                  filled: true,
                  fillColor: AppColors.card,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
                  ),
                ),
              ),
            ),
            Expanded(child: _buildRows(rows)),
          ],
        ),
      ),
    );
  }

  Widget _buildRows(List<_VaultRow> rows) {
    if (_entries.isEmpty && _codes.isEmpty) {
      return const Center(
        child: Text('Nothing in the vault yet.',
            style: TextStyle(color: Colors.white54)),
      );
    }
    if (rows.isEmpty) {
      return const Center(
        child: Text('No matches.', style: TextStyle(color: Colors.white54)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
      itemCount: rows.length,
      itemBuilder: (context, i) => _buildRow(rows[i]),
    );
  }

  Widget _buildRow(_VaultRow row) {
    final open = _openKey == row.key;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: open ? AppColors.accentMuted : AppColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _openKey = open ? null : row.key),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: open ? AppColors.accent : AppColors.border),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _letter(row.title),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  row.title,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (row.favorite) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.star, size: 14, color: Colors.amber),
                              ],
                            ],
                          ),
                          if (row.subtitle.isNotEmpty)
                            Text(
                              row.subtitle,
                              style: const TextStyle(color: AppColors.muted, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (open) ...[
                  if (row.entry != null && row.entry!.password.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('••••••••', style: TextStyle(color: AppColors.muted, letterSpacing: 1)),
                        const Spacer(),
                        TextButton(
                          onPressed: () => _copyToClipboard(row.entry!.password, autoClear: true),
                          child: const Text('Copy'),
                        ),
                      ],
                    ),
                  ],
                  if (row.code != null) _codeBlock(row.code!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _codeBlock(TotpCode code) {
    final revealed = _isRevealed(code.id);
    final shown = revealed
        ? code.code
        : '•' * (code.code.isEmpty ? 6 : code.code.length);
    final fraction = _period == 0 ? 0.0 : (_secondsRemaining / _period).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _copyToClipboard(code.code, autoClear: true),
                  child: Text(
                    shown,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      letterSpacing: revealed ? 3 : 2,
                      color: revealed ? AppColors.accent : Colors.white38,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  revealed ? Icons.visibility_off : Icons.visibility,
                  size: 20,
                  color: Colors.white54,
                ),
                tooltip: revealed ? 'Hide code' : 'Show code',
                onPressed: () => _toggleReveal(code.id),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 3,
              backgroundColor: AppColors.border,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            revealed
                ? 'Hides in ${_revealSecondsLeft(code.id)}s · ${_secondsRemaining}s left'
                : '${_secondsRemaining}s left',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _letter(String title) {
    final letter = title.trim().isEmpty ? '?' : title.trim()[0].toUpperCase();
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.wine,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(letter, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }

  List<_VaultRow> _visibleRows() {
    final needle = _query.trim().toLowerCase();
    final rows = _rows().where((row) {
      if (needle.isEmpty) return true;
      return row.title.toLowerCase().contains(needle) ||
          row.subtitle.toLowerCase().contains(needle);
    }).toList();
    return rows;
  }

  List<_VaultRow> _rows() {
    final used = <String>{};
    final rows = <_VaultRow>[];
    for (final entry in _entries) {
      final code = _codeFor(entry, used);
      if (code != null) used.add(code.id);
      rows.add(_VaultRow(
        key: 'entry:${entry.id}',
        title: entry.site.isEmpty ? 'Untitled' : entry.site,
        subtitle: entry.username,
        favorite: entry.favorite,
        entry: entry,
        code: code,
      ));
    }
    for (final code in _codes) {
      if (used.contains(code.id)) continue;
      final title = code.issuer.isNotEmpty ? code.issuer : code.name;
      final subtitle = code.issuer.isNotEmpty && code.name.isNotEmpty && code.name != code.issuer
          ? code.name
          : '';
      rows.add(_VaultRow(
        key: 'totp:${code.id}',
        title: title.isEmpty ? 'Authenticator' : title,
        subtitle: subtitle,
        favorite: false,
        code: code,
      ));
    }
    rows.sort((a, b) {
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return rows;
  }

  TotpCode? _codeFor(VaultEntry entry, Set<String> used) {
    if (entry.totpLinkId.isNotEmpty) {
      for (final code in _codes) {
        if (code.id == entry.totpLinkId && !used.contains(code.id)) return code;
      }
    }
    final site = entry.site.trim().toLowerCase();
    if (site.isEmpty) return null;
    for (final code in _codes) {
      if (used.contains(code.id)) continue;
      final issuer = code.issuer.trim().toLowerCase();
      final name = code.name.trim().toLowerCase();
      if (issuer == site || name == site) return code;
    }
    return null;
  }
}

class _VaultRow {
  final String key;
  final String title;
  final String subtitle;
  final bool favorite;
  final VaultEntry? entry;
  final TotpCode? code;

  const _VaultRow({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.favorite,
    this.entry,
    this.code,
  });
}
