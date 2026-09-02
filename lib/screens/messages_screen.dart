import 'dart:async';
import 'package:flutter/material.dart';
import '../models/message.dart';
import '../services/settings_service.dart';
import '../services/messaging_api_service.dart';
import '../services/local_notification_service.dart';
import '../theme/app_colors.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> with WidgetsBindingObserver {
  final _settings = SettingsService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  MessagingApiService? _api;
  String? _myDeviceId;
  final List<Message> _messages = [];
  bool _loading = true;
  bool _connected = false;
  bool _everConnected = false;

  StreamSubscription<Message>? _messagesSub;
  StreamSubscription<bool>? _connectionSub;

  // Suppresses the OS notification for a message that arrives while
  // this screen is actually the one on screen and the app is in the
  // foreground — you're already looking at it. AutomaticKeepAliveClientMixin
  // (see home_shell.dart's _KeepAlive) keeps this State alive even when
  // swiped away to another tab, so `mounted` alone can't tell us that;
  // AppLifecycleState only tells us foreground-vs-backgrounded, not which
  // tab is showing, so a message that arrives while some other tab is
  // open (but the app itself is foregrounded) still notifies — same
  // trade-off most single-conversation chat surfaces make.
  bool _appInForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LocalNotificationService.instance.init();
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messagesSub?.cancel();
    _connectionSub?.cancel();
    _api?.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed;
  }

  Future<void> _init() async {
    final base = await _settings.baseUrl('messages');
    _myDeviceId = await _settings.getOrCreateDeviceId();
    if (base == null) {
      setState(() => _loading = false);
      return;
    }

    final api = MessagingApiService(base);
    _messagesSub = api.messages.listen(_onIncoming);
    _connectionSub = api.connectionState.listen(_onConnectionChange);
    api.connect();

    setState(() {
      _api = api;
      _loading = false;
    });

    try {
      final history = await api.fetchHistory();
      if (mounted) {
        setState(() {
          _messages.addAll(history);
          _messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
        });
        _scrollToBottom();
      }
    } catch (_) {
      // Desktop unreachable on first load — the socket will keep
      // retrying in the background and history fills in once it's up.
    }
  }

  void _onConnectionChange(bool connected) async {
    if (!mounted) return;
    final wasConnected = _connected;
    setState(() => _connected = connected);
    if (connected && !wasConnected && _everConnected) {
      // Reconnected after a drop — pull anything sent while we were away.
      await _syncMissed();
    }
    if (connected) _everConnected = true;
  }

  Future<void> _syncMissed() async {
    if (_api == null) return;
    final since = _messages.isEmpty ? 0.0 : _messages.last.sentAt.millisecondsSinceEpoch / 1000;
    try {
      final missed = await _api!.fetchHistory(since: since);
      if (!mounted || missed.isEmpty) return;
      setState(() {
        for (final m in missed) {
          if (!_messages.any((existing) => existing.id == m.id)) {
            _messages.add(m);
          }
        }
        _messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
      });
      _scrollToBottom();
    } catch (_) {
      // Will retry on the next reconnect edge.
    }
  }

  void _onIncoming(Message message) {
    if (!mounted) return;
    final isNew = _messages.indexWhere((m) => m.id == message.id) < 0;
    setState(() {
      final i = _messages.indexWhere((m) => m.id == message.id);
      if (i >= 0) {
        // Echo of our own optimistic send — replace with the
        // server-confirmed copy instead of appending a duplicate.
        _messages[i] = message;
      } else {
        _messages.add(message);
      }
    });
    _scrollToBottom();

    // Only notify for messages actually from the other device (not our
    // own echoed send) and only when we're not already looking at the
    // app right now.
    if (isNew && message.senderId != _myDeviceId && !_appInForeground) {
      // Desktop always sends as the fixed id "desktop" (see
      // MessagingPage.DESKTOP_SENDER_ID on the PC side); anything else
      // is another paired phone.
      final label = message.senderId == 'desktop' ? 'Message from PC' : 'New message';
      LocalNotificationService.instance.showMessage(
        messageId: message.id,
        senderLabel: label,
        text: message.text,
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _send() {
    final text = _textController.text.trim();
    if (text.isEmpty || _api == null) return;
    if (!_connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected — message not sent')),
      );
      return;
    }

    final message = Message(
      id: Message.newId(),
      senderId: _myDeviceId!,
      text: text,
      sentAt: DateTime.now(),
    );

    setState(() => _messages.add(message));
    _textController.clear();
    _scrollToBottom();

    try {
      _api!.send(message);
    } catch (_) {
      // Dropped between the _connected check and now — leave the
      // bubble showing (it'll get de-duped if it does land after a
      // reconnect resend; there's no resend queue yet).
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_api == null) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Set your PC hostname in Settings first.',
                style: TextStyle(color: Colors.white54)),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _connected ? Icons.circle : Icons.circle_outlined,
                    size: 10,
                    color: _connected ? Colors.greenAccent : Colors.white38,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _connected ? 'Connected' : 'Reconnecting…',
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text('No messages yet.',
                        style: TextStyle(color: Colors.white54)),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) => _Bubble(
                      message: _messages[i],
                      isMine: _messages[i].senderId == _myDeviceId,
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Message…',
                        filled: true,
                        fillColor: AppColors.card,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send),
                    color: AppColors.accent,
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final Message message;
  final bool isMine;

  const _Bubble({required this.message, required this.isMine});

  String _formatTime(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final suffix = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $suffix';
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMine ? AppColors.wine : AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message.text, style: const TextStyle(color: AppColors.onSurface)),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.sentAt),
              style: const TextStyle(fontSize: 10, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
