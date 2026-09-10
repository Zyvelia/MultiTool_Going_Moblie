import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/inbox_bridge_service.dart';
import '../services/inbox_push_service.dart';
import '../theme/app_colors.dart';

class InboxLoginScreen extends StatefulWidget {
  const InboxLoginScreen({super.key});

  @override
  State<InboxLoginScreen> createState() => _InboxLoginScreenState();
}

class _InboxLoginScreenState extends State<InboxLoginScreen> {
  WebViewController? _controller;
  Timer? _poller;
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final controller = await InboxBridgeService.instance.createController(
        onError: (error) {
          if (mounted) setState(() => _error = error);
        },
      );
      if (!mounted) return;
      setState(() => _controller = controller);

      _poller = Timer.periodic(const Duration(seconds: 2), (_) => _check());
      await InboxBridgeService.instance.waitForPage();
      await _check();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _check() async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      final me = await InboxBridgeService.instance.me();
      final user = me['user'];
      if (user != null && me['isOwner'] == true) {
        await InboxPushService.instance.start();
        _poller?.cancel();
        if (mounted) Navigator.of(context).pop(true);
      } else if (user != null && me['isOwner'] != true) {
        if (mounted) {
          setState(() => _error = 'Signed in, but this account is not the Inbox owner.');
        }
      }
    } catch (_) {
      // OAuth may still be redirecting through Google/GitHub.
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox sign in'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: () => _controller?.reload(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: AppColors.card,
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
              ),
            ),
          Expanded(
            child: _controller == null
                ? const Center(child: CircularProgressIndicator())
                : WebViewWidget(controller: _controller!),
          ),
        ],
      ),
    );
  }
}
