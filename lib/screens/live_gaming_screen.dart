import 'dart:async';
import 'package:flutter/material.dart';
import '../services/live_server_client.dart';

class LiveGamingScreen extends StatefulWidget {
  const LiveGamingScreen({super.key,required this.client});
  final LiveServerClient client;
  @override
  State<LiveGamingScreen> createState()=>_LiveGamingScreenState();
}

class _LiveGamingScreenState extends State<LiveGamingScreen> {
  final _search=TextEditingController();
  final _games=<Map<String,dynamic>>[];
  String _kind='games',_query='';
  bool _busy=false,_allowed=false,_launch=false,_more=false;
  int _total=0;
  String? _message;
  LiveServerClient get api=>widget.client;

  @override
  void initState(){super.initState();unawaited(_load());}
  @override
  void dispose(){_search.dispose();super.dispose();}

  Future<void> _load({bool append=false}) async {
    if(_busy)return;
    setState((){
      _busy=true;_message=null;
      if(!append){_query=_search.text.trim();_games.clear();_total=0;_more=false;}
    });
    try {
      final caps=await api.capabilities();
      final allowed=caps[_kind=='games'?'games_read':'roms_read']==true;
      final data=allowed?await api.games(_kind,query:_query,offset:_games.length):null;
      if(!mounted)return;
      setState((){
        _allowed=allowed;_launch=data?['launch_allowed']==true;
        if(!allowed){_games.clear();_total=0;_more=false;}
        if(data!=null){
          _games.addAll((data['games'] as List).whereType<Map>().map((g)=>Map<String,dynamic>.from(g)));
          _total=data['total'] is int?data['total'] as int:_games.length;
          _more=data['has_more']==true;
        }
      });
    }catch(e){
      if(mounted)setState((){
        _games.clear();_total=0;_more=false;_allowed=false;_launch=false;
        _message=e is LiveServerException?e.message:'Could not reach the PC. Check Tailscale and Live Server.';
      });
    }finally{if(mounted)setState(()=>_busy=false);}
  }

  Future<void> _request(Map<String,dynamic> game)async{
    if(_busy||!_launch)return;
    final id=game['id'];
    if(id is! String||!LiveServerClient.validTrackId(id))return;
    final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Request launch on PC?'),
      content:Text('${game['title'] ?? 'Game'} will only launch if someone approves it on the desktop within two minutes.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Request'))]));
    if(yes!=true||!mounted||_busy)return;
    setState(()=>_busy=true);
    try{
      await api.requestGame(_kind,id);
      if(mounted)setState(()=>_message='Request queued, not launched. Review it on the PC Live Server page within two minutes.');
    }catch(e){
      if(mounted)setState(()=>_message='Request not confirmed. Check the pending request on PC before retrying.');
    }finally{if(mounted)setState(()=>_busy=false);}
  }

  String _time(Object? value){
    final s=value is num&&value.isFinite&&value>=0?value.toDouble():0.0;
    return s>=3600?'${(s/3600).toStringAsFixed(1)} h':'${(s/60).floor()} min';
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Live Gaming'),actions:[
      IconButton(tooltip:'Refresh library',onPressed:_busy?null:()=>_load(),icon:const Icon(Icons.refresh)),
    ]),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      SegmentedButton<String>(segments:const [
        ButtonSegment(value:'games',label:Text('PC games'),icon:Icon(Icons.computer)),
        ButtonSegment(value:'roms',label:Text('Emulator'),icon:Icon(Icons.sports_esports)),
      ],selected:{_kind},onSelectionChanged:_busy?null:(v){
        setState((){_kind=v.first;_search.clear();_allowed=false;_launch=false;});
        unawaited(_load());
      }),
      const SizedBox(height:16),
      TextField(controller:_search,enabled:!_busy,maxLength:200,textInputAction:TextInputAction.search,
        onSubmitted:(_)=>_load(),
        decoration:InputDecoration(labelText:'Search games',suffixIcon:IconButton(
          onPressed:_busy?null:()=>_load(),icon:const Icon(Icons.search)))),
      if(_busy)const LinearProgressIndicator(),
      if(_message!=null)Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Text(_message!)),
      if(!_allowed&&!_busy)const Text('Open the updated Gaming Hub or Emulator on your PC, grant library permission to this phone and enable the session sharing switch.'),
      if(_allowed)...[
        Text('$_total entries · ${_launch?'Launch requests enabled':'Read only'}'),
        const SizedBox(height:8),
        for(final game in _games)Card(child:ListTile(
          leading:Icon(game['active']==true?Icons.play_circle_outline:Icons.sports_esports_outlined),
          title:Text('${game['title'] ?? 'Game'}'),
          subtitle:Text('${game['platform'] ?? ''} · ${_time(game['seconds'])}${game['active']==true?' · Active':''}${game['favorite']==true?' · Favorite':''}'),
          trailing:_launch?IconButton(tooltip:'Request launch on PC',onPressed:_busy||game['active']==true?null:()=>_request(game),icon:const Icon(Icons.play_arrow)):null,
        )),
        if(_more)OutlinedButton(onPressed:_busy?null:()=>_load(append:true),child:const Text('Load more')),
        if(_games.isEmpty&&!_busy)const Text('No matching games.'),
      ],
      const SizedBox(height:16),
      const Text('Save transfers: create a backup on the PC and place it in Live Outbox. Use Live Quick Send to receive it or send a file to Inbox. Restore saves manually on the PC. ROM downloads and remote save-folder writes are not supported.'),
    ]));
}
