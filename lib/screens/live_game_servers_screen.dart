import 'dart:async';
import 'package:flutter/material.dart';
import '../services/live_server_client.dart';

class LiveGameServersScreen extends StatefulWidget {
  const LiveGameServersScreen({super.key,required this.client});
  final LiveServerClient client;
  @override
  State<LiveGameServersScreen> createState()=>_LiveGameServersScreenState();
}
class _LiveGameServersScreenState extends State<LiveGameServersScreen> with WidgetsBindingObserver {
  List<Map<String,dynamic>> _servers=[];
  bool _busy=false,_requesting=false,_foreground=true,_allowed=false;
  String? _error,_notice;
  Timer? _timer;
  int _generation=0;
  LiveServerClient get api=>widget.client;
  @override
  void initState(){super.initState();WidgetsBinding.instance.addObserver(this);_schedule(Duration.zero);}
  void _schedule([Duration delay=const Duration(seconds:3)]){
    _timer?.cancel();
    if(mounted&&_foreground)_timer=Timer(delay,()=>unawaited(_load()));
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state){
    _foreground=state==AppLifecycleState.resumed;
    if(!_foreground){
      ++_generation;_timer?.cancel();
      if(mounted)setState((){_servers=[];_allowed=false;});
    }else{_schedule(Duration.zero);}
  }
  Future<void> _load()async{
    if(!mounted||!_foreground)return;
    if(_busy||_requesting){_schedule();return;}
    final generation=_generation;
    setState(()=>_busy=true);
    try{
      final data=await api.gameServers();
      if(!mounted||!_foreground||generation!=_generation)return;
      final list=data['servers'];
      if(list is! List||list.length>200)throw const LiveServerException('Unexpected server list.');
      setState((){
        _servers=list.whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList();
        _allowed=true;_error=null;
      });
    }catch(e){
      if(mounted&&generation==_generation)setState((){
        _servers=[];_allowed=false;
        _error=e is LiveServerException?e.message:'Cannot reach the PC. Check Tailscale and Live Server.';
      });
    }finally{
      if(mounted){setState(()=>_busy=false);_schedule(_error==null?const Duration(seconds:3):const Duration(seconds:8));}
    }
  }
  Future<void> _request(Map<String,dynamic> server,String action)async{
    if(_requesting||!_foreground||!_allowed||server['can_'+action]!=true)return;
    final id=server['id'];
    if(id is! String||!LiveServerClient.validTrackId(id))return;
    setState(()=>_requesting=true);
    _timer?.cancel();
    try{
      final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
        title:Text('Request $action on PC?'),
        content:Text('${server['name']} · A local PC user must approve this request within two minutes. Stop uses the configured graceful command.'),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Request'))]));
      if(yes!=true||!mounted||!_foreground)return;
      await api.requestServerAction(id,action);
      if(mounted)setState(()=>_notice='Request queued, not executed. Review it on the PC Live Server page.');
    }catch(e){
      if(mounted)setState(()=>_notice='Request not confirmed. Check pending PC requests before retrying.');
    }finally{
      if(mounted){setState(()=>_requesting=false);_schedule(Duration.zero);}
    }
  }
  String _uptime(Object? value){
    if(value is! num||!value.isFinite||value<0)return 'Unavailable';
    final s=value.toInt();
    return '${s~/3600}h ${(s%3600)~/60}m ${s%60}s';
  }
  String _memory(Object? value)=>value is num&&value.isFinite&&value>=0?
    '${(value/1048576).toStringAsFixed(0)} MiB':'Unavailable';
  @override
  void dispose(){++_generation;_timer?.cancel();WidgetsBinding.instance.removeObserver(this);super.dispose();}
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Live Game Servers'),actions:[
      IconButton(tooltip:'Refresh servers',onPressed:_requesting||_busy?null:()=>_schedule(Duration.zero),icon:const Icon(Icons.refresh)),
    ]),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      Text('Registered PC servers',style:Theme.of(context).textTheme.headlineSmall),
      const Text('Private Tailscale connection · Local approval for actions'),
      if(_busy||_requesting)const LinearProgressIndicator(),
      if(_error!=null)Padding(padding:const EdgeInsets.all(8),child:Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      if(_notice!=null)Padding(padding:const EdgeInsets.all(8),child:Text(_notice!)),
      if(!_allowed&&!_busy)const Text('Open Game Server Manager 1.1.1 on PC. Grant server read permission and enable the session sharing switch.'),
      if(_allowed&&_servers.isEmpty&&!_busy)const Text('No registered profiles.'),
      for(final s in _servers)Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[
            Icon(s['running']==true?Icons.play_circle_outline:Icons.dns_outlined),
            const SizedBox(width:12),
            Expanded(child:Text('${s['name']??'Server'}',style:Theme.of(context).textTheme.titleLarge)),
          ]),
          Text('${s['kind']??'Custom'} · ${s['running']==true?'Process running':s['busy']==true?'Busy':'Not running in manager'}'),
          const SizedBox(height:8),
          Text('Uptime: ${_uptime(s['uptime'])}'),
          Text('Process RAM: ${_memory(s['memory'])}'),
          Text('Players: ${s['players']??'Unavailable'}'),
          Wrap(spacing:8,children:[
            if(s['can_start']==true)OutlinedButton.icon(onPressed:_requesting?null:()=>_request(s,'start'),icon:const Icon(Icons.play_arrow),label:const Text('Request start')),
            if(s['can_stop']==true)OutlinedButton.icon(onPressed:_requesting?null:()=>_request(s,'stop'),icon:const Icon(Icons.stop),label:const Text('Request stop')),
          ]),
        ]))),
      const SizedBox(height:12),
      const Text('Running means the managed process is alive, not that the server is ready for players. Only the saved selected idle profile can be started remotely. No console commands or forced shutdown are exposed.'),
    ]));
}
