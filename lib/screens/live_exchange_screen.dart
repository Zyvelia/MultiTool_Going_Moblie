import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/live_server_client.dart';

class LiveExchangeScreen extends StatefulWidget {
  const LiveExchangeScreen({super.key, required this.client, required this.notes});
  final LiveServerClient client;
  final bool notes;
  @override
  State<LiveExchangeScreen> createState() => _LiveExchangeScreenState();
}

class _LiveExchangeScreenState extends State<LiveExchangeScreen> {
  final _items = <Map<String,dynamic>>[];
  bool _read = false, _write = false, _busy = false, _more = false;
  String? _message;
  LiveServerClient get api => widget.client;
  @override
  void initState() { super.initState(); unawaited(_load()); }

  String _error(Object e) => e is LiveServerException ? e.message :
      'Request failed. Check Tailscale, the PC sharing switches and device permissions.';

  Future<void> _load({bool append = false}) async {
    if (_busy) return;
    setState(() { _busy = true; _message = null; if (!append) _items.clear(); });
    try {
      final caps = await api.capabilities();
      final read = caps[widget.notes ? 'notes_read' : 'files_download'] == true;
      final write = caps[widget.notes ? 'notes_edit' : 'files_upload'] == true;
      final data = read ? (widget.notes ? await api.notes(offset:_items.length) : await api.files()) : null;
      if (!mounted) return;
      setState(() {
        _read = read; _write = write; _more = data?['has_more'] == true;
        if (!read) _items.clear();
        if (data != null) _items.addAll((data[widget.notes ? 'notes' : 'files'] as List)
            .whereType<Map>().map((x)=>Map<String,dynamic>.from(x)));
      });
    } catch (e) {
      if (mounted) setState(() { _items.clear(); _read = false; _write = false; _more = false; _message = _error(e); });
    } finally { if (mounted) setState(()=>_busy=false); }
  }

  Future<void> _edit(Map<String,dynamic>? item) async {
    if (_busy) return;
    setState(()=>_busy=true);
    Map<String,dynamic>? note;
    try {
      if (item != null) note = await api.note(item['id'] as String);
      if (!mounted) return;
      final result = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => _NoteEditor(api:api, note:note, editable:_write)));
      if (mounted && result == true) _message = 'Note saved on PC.';
    } catch (e) { if (mounted) setState(()=>_message=_error(e)); }
    finally { if(mounted) setState(()=>_busy=false); }
    if (mounted) await _load();
  }

  Future<void> _upload() async {
    if (_busy || !_write) return;
    setState(()=>_busy=true);
    try {
      // Use the selected file's known size before reading into memory.
      final result = await FilePicker.platform.pickFiles(allowMultiple:false, withReadStream:true, withData:false);
      if (result == null || !mounted) return;
      final file = result.files.single;
      if (file.size > LiveServerClient.maxTransfer || file.readStream == null) {
        throw const LiveServerException('Choose a file up to 20 MiB.');
      }
      final bytes = <int>[];
      await for (final chunk in file.readStream!) {
        if (bytes.length + chunk.length > LiveServerClient.maxTransfer) throw const LiveServerException('File too large.');
        bytes.addAll(chunk);
      }
      if (!mounted) return;
      final name = file.name;
      final yes = await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('Send to PC?'),content:Text('$name will be saved in the PC Live Inbox.'),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Send'))]));
      if (yes != true || !mounted) return;
      await api.upload(name,bytes);
      if (mounted) setState(()=>_message='Sent to PC Inbox.');
    } catch(e) { if(mounted) setState(()=>_message=_error(e)); }
    finally { if(mounted) setState(()=>_busy=false); }
  }

  Future<void> _download(Map<String,dynamic> item) async {
    if (_busy || !_read) return;
    setState(()=>_busy=true);
    try {
      final bytes = await api.download(item['id'] as String);
      if (!mounted) return;
      final result = await FilePicker.platform.saveFile(
        dialogTitle:'Save received file',fileName:item['name'] as String,
        bytes:Uint8List.fromList(bytes));
      if (mounted) setState(()=>_message=result==null?'Save cancelled.':'File saved.');
    } catch(e) { if(mounted) setState(()=>_message=_error(e)); }
    finally { if(mounted) setState(()=>_busy=false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar:AppBar(title:Text(widget.notes?'Live Notes':'Live Quick Send'),
      actions:[IconButton(tooltip:'Refresh',onPressed:_busy?null:()=>_load(),icon:const Icon(Icons.refresh))]),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      Text(widget.notes?'Shared Mobile folder':'Private Inbox / Outbox',style:Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height:8),
      Text(widget.notes?'Only notes inside the PC Mobile folder are shared. Changes require a matching revision.':
        'Download files placed in the PC Live Outbox, or send a file to Live Inbox. Maximum 20 MiB per file.'),
      const SizedBox(height:12),
      if (!_read && !_write) const Text('Sharing not enabled. Grant this paired device permission on the PC Live Server page.'),
      if (_write) FilledButton.icon(onPressed:_busy?null:widget.notes?()=>_edit(null):_upload,
        icon:Icon(widget.notes?Icons.add:Icons.upload_file),label:Text(widget.notes?'New shared note':'Send file to PC')),
      if (_message != null) Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(_message!)),
      if (_busy) const LinearProgressIndicator(),
      if (_read && _items.isEmpty && !_busy) Text(widget.notes?'No shared notes.':'Outbox is empty.'),
      for (final item in _items) Card(child:ListTile(
        leading:Icon(widget.notes?Icons.note_alt_outlined:Icons.insert_drive_file_outlined),
        title:Text('${item[widget.notes?'title':'name'] ?? ''}'),
        subtitle:widget.notes?null:Text('${item['size'] ?? 0} bytes'),
        trailing:Icon(widget.notes?Icons.chevron_right:Icons.download),
        enabled:!_busy,onTap:()=>widget.notes?_edit(item):_download(item))),
      if (_more) OutlinedButton(onPressed:_busy?null:()=>_load(append:true),child:const Text('Load more')),
    ]));
}

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({required this.api,required this.note,required this.editable});
  final LiveServerClient api;
  final Map<String,dynamic>? note;
  final bool editable;
  @override
  State<_NoteEditor> createState()=>_NoteEditorState();
}
class _NoteEditorState extends State<_NoteEditor> {
  late final TextEditingController title,body;
  bool busy=false;
  String? error;
  @override
  void initState(){super.initState();title=TextEditingController(text:widget.note?['title'] as String? ?? '');body=TextEditingController(text:widget.note?['body'] as String? ?? '');}
  @override
  void dispose(){title.dispose();body.dispose();super.dispose();}
  Future<void> save() async {
    if(busy||!widget.editable)return;
    setState(()=>busy=true);
    try {
      await widget.api.saveNote(title.text,body.text,id:widget.note?['id'] as String?,revision:widget.note?['revision'] as String?);
      if(mounted)Navigator.pop(context,true);
    }catch(e){if(mounted)setState(()=>error='Save not confirmed. The note may have changed, the PC editor may have unsaved changes, or permission was revoked. Copy your draft before reloading.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Shared note'),actions:[if(widget.editable)TextButton(onPressed:busy?null:save,child:const Text('Save'))]),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      TextField(controller:title,maxLength:240,readOnly:!widget.editable||busy,decoration:const InputDecoration(labelText:'Title')),
      TextField(controller:body,maxLength:100000,minLines:10,maxLines:25,readOnly:!widget.editable||busy,decoration:const InputDecoration(labelText:'Markdown body')),
      if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
      if(busy)const LinearProgressIndicator(),
    ]));
}
