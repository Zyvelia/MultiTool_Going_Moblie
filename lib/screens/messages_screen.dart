import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/inbox_message.dart';
import '../services/inbox_bridge_service.dart';
import '../services/inbox_push_service.dart';
import '../theme/app_colors.dart';

/// Native Inbox screen.
///
/// The WebView is used only for Better Auth login. It stays mounted in an
/// offstage layer after authentication so its httpOnly session cookie remains
/// available to the bridge. Messages themselves are always rendered natively.
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
  bool _authReady = false;
  String? _error;
  WebViewController? _authController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeInbox();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller?.cancel();
    _scrollController.dispose();
    // Do not invalidate the bridge controller here. The WebView controller is
    // intentionally owned by the Inbox bridge for the lifetime of the app.
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load(silent: true);
    }
  }

  Future<void> _initializeInbox() async {
    await _prepareAuthWebView();
    if (mounted) await _load();
  }

  Future<void> _prepareAuthWebView() async {
    try {
      final controller = await InboxBridgeService.instance.ensureController();
      if (!mounted) return;
      setState(() {
        _authController = controller;
        _authReady = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _authReady = true;
          _error = 'Could not open Inbox sign-in.';
        });
      }
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent && mounted) setState(() => _loading = true);

    try {
      final me = await InboxBridgeService.instance.me();
      final user = me['user'];
      final owner = me['isOwner'] == true;

      if (user == null || !owner) {
        if (mounted) {
          setState(() {
            _signedIn = false;
            _loading = false;
            if (user is Map && !owner) {
              final email = user['email']?.toString() ?? '';
              _error = email.isEmpty
                  ? 'This account is not the Inbox owner.'
                  : 'Signed in as $email, but this account is not the Inbox owner.';
            } else {
              _error = null;
            }
          });
        }
        _startPolling();
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
            if (!_messages.any((m) => m.id == message.id)) {
              _messages.add(message);
            }
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
          if (_signedIn) {
            _error = 'Could not refresh Inbox.';
          } else {
            _startPolling();
          }
        });
      }
    } finally {
      _refreshing = false;
    }
  }

  void _startPolling() {
    _poller ??= Timer.periodic(
      const Duration(seconds: 5),
      (_) => _load(silent: true),
    );
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

  Widget _authLayer() {
    return Offstage(
      offstage: _signedIn,
      child: _authController == null
          ? const Center(child: CircularProgressIndicator())
          : WebViewWidget(controller: _authController!),
    );
  }

  Widget _nativeInbox() {
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
                  Center(
                    child: Text(
                      'No messages yet.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * .82,
                      ),
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
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.accent,
                                  ),
                                ),
                              ),
                              Text(
                                _formatTime(message.createdAt),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                          if (message.senderEmail.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              message.senderEmail,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.muted,
                              ),
                            ),
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

  Widget _loginFallback() {
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: Stack(
        children: [
          _authLayer(),
          if (_authReady && _error != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Material(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                elevation: 6,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.orangeAccent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && !_signedIn) {
      // Keep the WebView mounted while checking the session. Once the page is
      // ready it becomes the login surface instead of showing the inbox web UI.
      return Stack(
        children: [
          _authLayer(),
          if (!_authReady)
            const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
        ],
      );
    }

    if (!_signedIn) return _loginFallback();

    // Keep the authenticated WebView mounted offstage while the native inbox
    // is visible. This is the key to retaining Better Auth's httpOnly cookie.
    return Stack(
      children: [
        _nativeInbox(),
        _authLayer(),
      ],
    );
  }
}
