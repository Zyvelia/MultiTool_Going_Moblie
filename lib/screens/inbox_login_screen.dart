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
  bool _authenticated = false;
  String? _signedInEmail;
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
          if (mounted && !_authenticated) {
            setState(() => _error = error);
          }
        },
      );

      if (!mounted) return;
      setState(() => _controller = controller);

      // Check after every navigation as OAuth redirects back to the Worker.
      _poller = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _checkSession(),
      );

      await InboxBridgeService.instance.waitForPage();
      await _checkSession();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _checkSession() async {
    if (_checking || !mounted) return;
    _checking = true;

    try {
      final me = await InboxBridgeService.instance.sessionInfo();
      final user = me['user'];

      if (user is Map) {
        final email = user['email']?.toString() ?? '';
        final owner = me['isOwner'] == true;

        if (owner) {
          _poller?.cancel();
          setState(() {
            _authenticated = true;
            _signedInEmail = email;
            _error = null;
          });

          await InboxPushService.instance.start();

          if (!mounted) return;
          // Return to the native Messages screen. The Worker website is
          // only used as the authentication surface, never as the inbox UI.
          Navigator.of(context).pop(true);
          return;
        }

        if (email.isNotEmpty) {
          setState(() {
            _authenticated = true;
            _signedInEmail = email;
            _error =
                'Signed in as $email, but this account is not the Inbox owner.';
          });
        }
      }
    } catch (_) {
      // OAuth redirects can temporarily make /api/me unavailable.
      // Keep polling until the Worker session is established.
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
      body: Stack(
        children: [
          if (_controller != null)
            WebViewWidget(controller: _controller!)
          else
            const Center(child: CircularProgressIndicator()),

          if (_error != null || _authenticated)
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
                      Icon(
                        _authenticated
                            ? Icons.account_circle_outlined
                            : Icons.error_outline,
                        color: _authenticated
                            ? AppColors.accent
                            : Colors.orangeAccent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error ??
                              (_signedInEmail == null
                                  ? 'Checking Inbox sign-in…'
                                  : 'Signed in as $_signedInEmail'),
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
}
