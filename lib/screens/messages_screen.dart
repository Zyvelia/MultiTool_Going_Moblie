import 'dart:async';

import 'package:flutter/material.dart';

import '../models/inbox_message.dart';
import '../services/inbox_bridge_service.dart';
import '../services/inbox_push_service.dart';
import '../theme/app_colors.dart';
import 'inbox_login_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
    with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  final _messages = <InboxMessage>[];

  Timer? _poller;
  bool _loading = true;
  bool _signedIn = false;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _signedIn) {
      _load(silent: true);
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent && mounted) setState(() => _loading = true);

    try {
      // The login WebView is intentionally temporary. Its Better Auth cookie
      // survives route disposal, but its native WebViewController does not.
      // InboxBridgeService creates a fresh controller here when necessary.
      final me = await InboxBridgeService.instance.me();
      final user = me['user'];
      final owner = me['isOwner'] == true;

      if (user == null || !owner) {
        if (mounted) {
          setState(() {
            _signedIn = false;
            _error = null;
            _loading = false;
          });
        }
        _poller?.cancel();
        return;
      }

      final since = _messages.isEmpty
          ? null
          : _messages.last.createdAt.millisecondsSinceEpoch;
      final incoming = await InboxBridgeService.instance.fetchMessages(since: since);

      if (mounted) {
        setState(() {
          _signedIn = true;
          _error = null;
          for (final message in incoming) {
            if (!_messages.any((m) => m.id == message.id)) _messages.add(message);
          }
          _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          _loading = false;
        });
        _startPolling();
        _scrollToBottom();
      }
      await InboxPushService.instance.start();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (_signedIn) _error = 'Could not refresh Inbox.';
        });
      }
    } finally {
      _refreshing = false;
    }
  }

  void _startPolling() {
    _poller ??= Timer.periodic(const Duration(seconds: 10), (_) => _load(silent: true));
  }

  Future<void> _signIn() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const InboxLoginScreen()),
    );
    if (ok == true) await _load();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  String _formatTime(DateTime time) {
    final h = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m ${time.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && !_signedIn) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_signedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Messages')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 46, color: AppColors.muted),
                const SizedBox(height: 14),
                const Text(
                  'Sign in to your Inbox',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your messages are protected by the Inbox Worker account.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: _signIn,
                  icon: const Icon(Icons.login),
                  label: const Text('Sign in'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _messages.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 260),
                  Center(child: Text('No messages yet.', style: TextStyle(color: AppColors.muted))),
                ],
              )
            : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .82),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  message.senderName,
                                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.accent),
                                ),
                              ),
                              Text(_formatTime(message.createdAt),
                                  style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                            ],
                          ),
                          if (message.senderEmail.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(message.senderEmail,
                                style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                          ],
                          const SizedBox(height: 7),
                          Text(message.text),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
