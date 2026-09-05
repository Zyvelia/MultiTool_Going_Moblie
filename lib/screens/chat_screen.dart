import 'dart:async';
import 'package:flutter/material.dart';
import '../models/ai_message.dart';
import '../services/ai_api_service.dart';
import '../services/settings_service.dart';
import '../services/user_facing_error.dart';
import '../theme/app_colors.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _settings = SettingsService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  AiApiService? _api;
  final List<AiMessage> _messages = [];
  AiChatStatus? _status;
  bool _loading = true;
  bool _sending = false;
  bool _agent = true;
  String? _error;
  Timer? _confirmPoll;
  bool _confirmOpen = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _stopConfirmPoll();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final base = await _settings.baseUrl('chat');
    final code = await _settings.getAccessCode('chat');
    if (base == null) {
      setState(() {
        _loading = false;
        _error = 'Set your PC hostname in Settings.';
      });
      return;
    }
    setState(() => _api = AiApiService(base, accessCode: code));
    await _autoConnect();
    await _refresh();
  }

  Future<void> _autoConnect() async {
    if (_api == null) return;
    final source = await _settings.getChatSource();
    try {
      if (source == 'local') {
        final status = await _api!.connect(source: 'local');
        if (mounted) setState(() => _status = status);
        return;
      }
      final key = await _settings.getChatApiKey();
      if (key == null || key.isEmpty) return;
      final status = await _api!.connect(
        source: 'hosted',
        apiKey: key,
        baseUrl: await _settings.getChatBaseUrl(),
        model: await _settings.getChatModel(),
      );
      if (mounted) setState(() => _status = status);
    } catch (_) {
      // Status banner will show the PC error after _refresh.
    }
  }

  Future<void> _refresh() async {
    if (_api == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await _api!.status();
      final history = await _api!.history();
      setState(() {
        _status = status;
        _messages
          ..clear()
          ..addAll(history);
        _loading = false;
        if (!status.ready && status.error.isNotEmpty) {
          _error = explainError(status.error);
        }
      });
      _jumpToEnd();
    } catch (e) {
      setState(() {
        _error = explainError(e);
        _loading = false;
      });
    }
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _api == null || _sending) return;
    _textController.clear();
    setState(() {
      _sending = true;
      _error = null;
      _messages.add(AiMessage(role: 'user', content: text));
    });
    _jumpToEnd();
    _startConfirmPoll();
    try {
      final result = await _api!.send(text, agent: _agent);
      setState(() {
        if (result.cleared) {
          _messages.clear();
        }
        for (final tool in result.tools) {
          final ok = tool['ok'] == true;
          _messages.add(AiMessage(
            role: 'tool',
            content: '${tool['name']} → ${ok ? 'ok' : 'fail'}: ${tool['detail']}',
          ));
        }
        if (result.reply.isNotEmpty) {
          _messages.add(AiMessage(role: 'assistant', content: result.reply));
        }
        _sending = false;
      });
      _jumpToEnd();
    } catch (e) {
      setState(() {
        _sending = false;
        _error = explainError(e);
      });
    } finally {
      _stopConfirmPoll();
    }
  }

  void _startConfirmPoll() {
    _stopConfirmPoll();
    _confirmPoll = Timer.periodic(const Duration(milliseconds: 700), (_) {
      _pollConfirm();
    });
  }

  void _stopConfirmPoll() {
    _confirmPoll?.cancel();
    _confirmPoll = null;
  }

  Future<void> _pollConfirm() async {
    if (_confirmOpen || _api == null || !mounted) return;
    Map<String, dynamic>? pending;
    try {
      pending = await _api!.pendingConfirm();
    } catch (_) {
      return;
    }
    if (pending == null || !mounted) return;
    _confirmOpen = true;
    final name = pending['name']?.toString() ?? 'action';
    final args = pending['args']?.toString() ?? '';
    final id = pending['id']?.toString() ?? '';
    final allow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Allow on the PC?'),
        content: Text(args.isEmpty ? name : '$name\n\n$args'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Deny')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Allow')),
        ],
      ),
    );
    try {
      if (id.isNotEmpty) {
        await _api!.answerConfirm(id, allow == true);
      }
    } catch (_) {}
    _confirmOpen = false;
  }

  Future<void> _openConnect() async {
    if (_api == null) return;
    final source = await _settings.getChatSource();
    final urlCtrl = TextEditingController(
      text: (await _settings.getChatBaseUrl()) ?? (_status?.hostedBaseUrl ?? 'https://api.xkiro.com/v1'),
    );
    final modelCtrl = TextEditingController(
      text: (await _settings.getChatModel()) ?? (_status?.model ?? 'deepseek/deepseek-v4-flash'),
    );
    final keyCtrl = TextEditingController(text: await _settings.getChatApiKey() ?? '');
    var picked = source;
    if (!mounted) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (ctx, setSheet) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Connect to the PC model', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text(
                    'Hosted key is saved on this phone only. The PC keeps it in memory for this session.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'hosted', label: Text('Hosted')),
                      ButtonSegment(value: 'local', label: Text('Local')),
                    ],
                    selected: {picked},
                    onSelectionChanged: (s) => setSheet(() => picked = s.first),
                  ),
                  if (picked == 'hosted') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: urlCtrl,
                      decoration: const InputDecoration(labelText: 'Base URL', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: modelCtrl,
                      decoration: const InputDecoration(labelText: 'Model', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: keyCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'API key', border: OutlineInputBorder()),
                    ),
                  ] else
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Uses the local model already picked in AI Chat on the PC (Ollama / llama.cpp).',
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Connect'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
    if (ok != true) {
      urlCtrl.dispose();
      modelCtrl.dispose();
      keyCtrl.dispose();
      return;
    }
    final url = urlCtrl.text.trim();
    final model = modelCtrl.text.trim();
    final key = keyCtrl.text.trim();
    urlCtrl.dispose();
    modelCtrl.dispose();
    keyCtrl.dispose();
    await _settings.setChatSource(picked);
    await _settings.setChatBaseUrl(url);
    await _settings.setChatModel(model);
    await _settings.setChatApiKey(key);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final status = await _api!.connect(
        source: picked,
        apiKey: key,
        baseUrl: url,
        model: model,
      );
      if (!mounted) return;
      setState(() {
        _status = status;
        _sending = false;
        _error = status.ready ? null : explainError(status.error);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = explainError(e);
      });
    }
  }

  Future<void> _clear() async {
    if (_api == null) return;
    try {
      await _api!.clear();
      setState(_messages.clear);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(explainError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _status == null
        ? ''
        : [
            _status!.source,
            if (_status!.model.isNotEmpty) _status!.model,
            if (_status!.ready) 'ready' else 'not ready',
          ].join(' · ');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI Chat'),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        actions: [
          Row(
            children: [
              const Text('Agent', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              Switch(
                value: _agent,
                onChanged: _sending ? null : (v) => setState(() => _agent = v),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Connect',
            onPressed: _sending ? null : _openConnect,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _clear),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Material(
              color: AppColors.wine,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Text(_error!, style: const TextStyle(color: AppColors.onSurface, fontSize: 13)),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: _messages.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Connect (link icon) then talk. Agent runs tools on the PC. '
                                '/build a python snake game   — writes files under AI_Projects. '
                                '/help for the rest. Writes may confirm on the desktop.',
                                style: TextStyle(color: Colors.white54),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: _messages.length + (_sending ? 1 : 0),
                            itemBuilder: (context, i) {
                              if (i == _messages.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text('Thinking on the PC…', style: TextStyle(color: AppColors.muted)),
                                );
                              }
                              return _Bubble(message: _messages[i]);
                            },
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
                      enabled: !_sending,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Ask, or /build … /help',
                        filled: true,
                        fillColor: AppColors.card,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                    onPressed: _sending ? null : _send,
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
  final AiMessage message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isTool = message.isTool;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: isTool
              ? const Color(0xFF2A1830)
              : isUser
                  ? AppColors.wine
                  : AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          message.content,
          style: TextStyle(
            color: isTool ? const Color(0xFFD2A8FF) : AppColors.onSurface,
            fontSize: isTool ? 12 : 14,
          ),
        ),
      ),
    );
  }
}
