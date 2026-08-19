import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../models/vault_entry.dart';
import '../services/settings_service.dart';
import '../services/vault_api_service.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen>
    with SingleTickerProviderStateMixin {
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

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _init();
  }

  Future<void> _init() async {
    final base = await _settings.baseUrl('vault');
    if (base != null) {
      setState(() => _api = VaultApiService(base));
    }
  }

  @override
  void dispose() {
    _totpTimer?.cancel();
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
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
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
    });
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
    );
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
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEntries(),
          _buildTotp(),
        ],
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
            onPressed: () => _copyToClipboard(e.password),
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
        return ListTile(
          leading: const Icon(Icons.shield_outlined, color: Colors.white38),
          title: Text(c.issuer.isNotEmpty ? c.issuer : c.name),
          subtitle: Text(c.name),
          trailing: Text(
            c.code,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.accent,
            ),
          ),
          onTap: () => _copyToClipboard(c.code),
        );
      },
    );
  }
}
