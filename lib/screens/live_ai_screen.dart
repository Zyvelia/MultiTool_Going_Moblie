import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/live_server_client.dart';

class LiveAiScreen extends StatefulWidget {
  const LiveAiScreen({super.key, required this.client});
  final LiveServerClient client;
  @override
  State<LiveAiScreen> createState() => _LiveAiScreenState();
}

class _LiveAiScreenState extends State<LiveAiScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <Map<String,String>>[];
  String? _model, _job, _error;
  String _partial = '';
  bool _busy = false, _loading = false, _cancelling = false;
  LiveServerClient get api => widget.client;

  @override
  void initState() { super.initState(); unawaited(_load()); }

  Future<void> _load() async {
    if (_busy || _loading) return;
    setState(() { _loading = true; _error = null; });
    try {
      final caps = await api.capabilities();
      if (caps['ai_chat'] != true) throw const LiveServerException('Enable AI permission and an approved local Ollama model on the PC.');
      final data = await api.aiModels();
      final models = (data['models'] as List).whereType<String>().toList();
      if (models.length != 1) throw const LiveServerException('No approved model is available.');
      if (mounted) setState(() => _model = models.single);
    } catch (e) {
      if (mounted) setState(() { _model = null; _error = e is LiveServerException ? e.message : 'Cannot reach the PC. Check Live Server and Tailscale.'; });
    } finally { if (mounted) setState(() => _loading = false); }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final prompt = _input.text.trim(), model = _model;
    if (_busy || _loading || model == null || prompt.isEmpty || prompt.length > 30000) return;
    // Keep complete user/assistant pairs, with a bounded request context.
    final context = <Map<String,String>>[{'role':'user','content':prompt}];
    int used = prompt.length;
    for (int i = _messages.length - 2; i >= 0 && context.length < 15; i -= 2) {
      final u = _messages[i], a = _messages[i+1];
      final size = u['content']!.length + a['content']!.length;
      if (u['role'] != 'user' || a['role'] != 'assistant' ||
          u['content']!.length > 30000 || a['content']!.length > 30000 || used + size > 60000) break;
      context.insertAll(0,[u,a]); used += size;
    }
    setState(() { _busy = true; _error = null; _partial = ''; _messages.add({'role':'user','content':prompt}); _input.clear(); });
    _toBottom();
    String? job;
    bool completed = false;
    try {
      job = await api.aiStart(model, context);
      if (!mounted) { await api.aiCancel(job).catchError((Object _) {}); return; }
      setState(() => _job = job);
      final deadline = DateTime.now().add(const Duration(minutes:4));
      while (mounted && DateTime.now().isBefore(deadline)) {
        final result = await api.aiResult(job);
        if (!mounted) break;
        final text = result['text'], status = result['status'];
        if (text is! String || text.length > 100000 ||
            !const {'generating','complete','cancelled','error'}.contains(status)) {
          throw const LiveServerException('Unexpected AI response.');
        }
        setState(() => _partial = text);
        _toBottom();
        if (status != 'generating') {
          completed = status == 'complete' && text.isNotEmpty;
          if (!completed) setState(() => _error = status == 'cancelled' ? 'Generation stopped.' : 'No complete response. Check Ollama and the approved model on the PC.');
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds:700));
      }
      if (mounted && DateTime.now().isAfter(deadline)) setState(() => _error = 'Generation timed out.');
    } catch (e) {
      if (mounted) setState(() => _error = e is LiveServerException ? e.message : 'Connection lost. The PC may still be generating; requests are not automatically retried.');
    } finally {
      if (job != null && !completed) { try { await api.aiCancel(job); } catch (_) {} }
      if (mounted) {
        setState(() {
          // Keep only complete turns in subsequent model context. On error,
          // return the original prompt to the editor and display partial text.
          if (completed) {
            _messages.add({'role':'assistant','content':_partial});
            _partial = '';
            if (_messages.length > 80) _messages.removeRange(0,2);
          } else {
            _messages.removeLast();
            _input.text = prompt;
          }
          _job = null; _busy = false; _cancelling = false;
        });
        _toBottom();
      }
    }
  }

  Future<void> _cancel() async {
    final id = _job;
    if (id == null || _cancelling) return;
    setState(() => _cancelling = true);
    try { await api.aiCancel(id); }
    catch (_) { if (mounted) setState(() { _error = 'Cancellation not confirmed. The PC also enforces a generation timeout.'; _cancelling = false; }); }
  }

  @override
  void dispose() {
    final id = _job;
    if (id != null) unawaited(api.aiCancel(id).catchError((Object _) {}));
    _input.dispose(); _scroll.dispose();
    super.dispose();
  }

  Widget _bubble(String role, String text) => Align(
    alignment: role == 'user' ? Alignment.centerRight : Alignment.centerLeft,
    child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
      children: [
        Text(role == 'user' ? 'YOU' : 'OLLAMA', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height:6), SelectableText(text),
        if (role != 'user') TextButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text:text)),
          icon:const Icon(Icons.copy,size:16),label:const Text('Copy')),
      ]))));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title:const Text('Live AI Chat'), actions:[
      IconButton(tooltip:'Refresh model',onPressed:_busy||_loading?null:_load,icon:const Icon(Icons.refresh)),
      IconButton(tooltip:'New conversation',onPressed:_busy?null:()=>setState((){_messages.clear();_partial='';_error=null;_input.clear();}),icon:const Icon(Icons.add_comment_outlined)),
    ]),
    body: SafeArea(child: Column(children:[
      Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text(_model ?? 'No approved model',style:Theme.of(context).textTheme.titleMedium),
        const Text('Local Ollama · Private Live Server · Text only'),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      ])),
      Expanded(child:ListView(controller:_scroll,padding:const EdgeInsets.symmetric(horizontal:12),children:[
        if (_messages.isEmpty && _partial.isEmpty) const Padding(padding:EdgeInsets.all(24),child:Text('Start a conversation. Your PC runs the approved model; no cloud API credentials are sent to your phone.')),
        for(final m in _messages) _bubble(m['role']!,m['content']!),
        if(_partial.isNotEmpty) _bubble('assistant',_partial),
        if(_busy) const Padding(padding:EdgeInsets.all(10),child:LinearProgressIndicator()),
      ])),
      Padding(padding:const EdgeInsets.all(12),child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
        Expanded(child:TextField(controller:_input,enabled:!_busy,maxLength:30000,minLines:1,maxLines:5,
          decoration:const InputDecoration(labelText:'Message',border:OutlineInputBorder()))),
        if(_busy) IconButton(tooltip:'Stop generation',onPressed:_job==null||_cancelling?null:_cancel,icon:const Icon(Icons.stop_circle))
        else IconButton(tooltip:'Send',onPressed:_model==null||_loading?null:_send,icon:const Icon(Icons.send)),
      ])),
    ])));
}
