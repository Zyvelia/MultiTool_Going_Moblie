import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import '../services/live_server_client.dart';
import '../services/audio_background.dart';

/// The C# Live Server library is independent of the legacy music API.
/// Playback is deliberately scoped to this screen and stopped on exit.
/// The existing app uses just_audio_background's single-player session;
/// do not use this screen simultaneously with legacy music playback.
class LiveMusicScreen extends StatefulWidget {
  const LiveMusicScreen({super.key, required this.client});
  final LiveServerClient client;
  @override
  State<LiveMusicScreen> createState() => _LiveMusicScreenState();
}

class _LiveMusicScreenState extends State<LiveMusicScreen> with WidgetsBindingObserver {
  final _search = TextEditingController();
  AudioPlayer? _player;
  final _songs = <Map<String,dynamic>>[];
  Map<String,dynamic>? _media;
  Map<String,dynamic>? _current;
  bool _stream = false, _control = false, _busy = false, _more = false;
  bool _pc = false, _opening = false, _foreground = true;
  String? _error;
  Timer? _timer;
  int _epoch = 0;
  double? _seek;
  LiveServerClient get api => widget.client;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load(reset: true));
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => unawaited(_status()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(_status());
    else unawaited(_stopPhone());
  }

  Future<void> _stopPhone() async {
    try { await _player?.stop(); } catch (_) {}
  }
  Future<void> _status() async {
    if (!mounted || !_foreground || _busy || _opening) return;
    final epoch = _epoch;
    try {
      final caps = await api.capabilities();
      final data = await api.state();
      if (!mounted || epoch != _epoch) return;
      final stream = caps['music_streaming'] == true;
      final control = caps['remote_actions'] == true;
      if (!stream) await _stopPhone();
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _stream = stream; _control = control;
        _media = data['media'] is Map ? Map<String,dynamic>.from(data['media'] as Map) : null;
        if (!stream) { _songs.clear(); _more = false; _current = null; }
      });
    } catch (_) {
      await _stopPhone();
      if (mounted && epoch == _epoch) setState(() {
        _stream = false; _control = false; _media = null; _songs.clear(); _more = false; _current = null;
        _error = 'Connection lost or permission revoked. Reconnect or refresh after checking ZMT.';
      });
    }
  }

  Future<void> _load({required bool reset}) async {
    if (_busy || _opening) return;
    final epoch = ++_epoch;
    setState(() { _busy = true; _error = null; if (reset) {_songs.clear(); _more = false;} });
    try {
      final caps = await api.capabilities();
      final stream = caps['music_streaming'] == true, control = caps['remote_actions'] == true;
      final state = await api.state();
      final page = stream ? await api.musicLibrary(query: _search.text.trim(), offset: _songs.length) : null;
      if (!mounted || epoch != _epoch) return;
      if (!stream) await _stopPhone();
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _stream = stream; _control = control;
        _media = state['media'] is Map ? Map<String,dynamic>.from(state['media'] as Map) : null;
        if (!stream) { _songs.clear(); _more = false; _current = null; }
        if (page != null) {
          _songs.addAll((page['songs'] as List).whereType<Map>().map((s) => Map<String,dynamic>.from(s)));
          _more = page['has_more'] == true;
        }
      });
    } catch (_) {
      await _stopPhone();
      if (mounted && epoch == _epoch) setState(() {
        _stream = false; _control = false; _songs.clear(); _more = false; _media = null; _current = null;
        _error = 'Unable to load live music. Check the paired device permissions and Media Player on the PC.';
      });
    } finally { if (mounted && epoch == _epoch) setState(() => _busy = false); }
  }

  Future<void> _playTrack(Map<String,dynamic> song) async {
    if (_opening || _busy || !_foreground) return;
    final id = song['id'];
    if (id is! String || !LiveServerClient.validTrackId(id)) return;
    if (_pc) { await _command('play_track', id: id); return; }
    if (!_stream) return;
    setState(() { _opening = true; _error = null; });
    try {
      await ensureAudioBackground();
      if (!mounted || !_foreground) return;
      final p = _player ??= AudioPlayer();
      await p.stop();
      if (!mounted || !_foreground) return;
      await p.setAudioSource(AudioSource.uri(api.musicUri(id), headers: api.musicHeaders,
        tag: MediaItem(id: id, title: '${song['title'] ?? 'Track'}',
          artist: '${song['artist'] ?? ''}', album: '${song['album'] ?? ''}')));
      if (!mounted || !_foreground || !_stream) { await p.stop(); return; }
      setState(() => _current = song);
      unawaited(p.play().catchError((Object _) {
        if (mounted) setState(() => _error = 'Phone playback failed. Check the audio format and connection.');
      }));
    } catch (_) {
      await _stopPhone();
      if (mounted) setState(() => _error = 'Could not start phone playback. Stop legacy mobile playback first and check the audio format.');
    } finally { if (mounted) setState(() => _opening = false); }
  }

  Future<void> _command(String action, {String? id, double? value}) async {
    if (!_control || _opening || _busy) return;
    setState(() { _opening = true; _error = null; });
    try { await api.musicControl(action, id: id, value: value); }
    catch (_) { if (mounted) setState(() => _error = 'PC command was not confirmed. Refresh status before retrying.'); }
    finally { if (mounted) { setState(() => _opening = false); unawaited(_status()); } }
  }

  String _clock(double n) {
    final s = n.isFinite && n >= 0 ? n.toInt() : 0;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2,'0')}';
  }
  double _number(Object? n) => n is num && n.isFinite && n >= 0 ? n.toDouble() : 0;

  @override
  void dispose() {
    ++_epoch; _timer?.cancel(); WidgetsBinding.instance.removeObserver(this);
    _search.dispose(); final player = _player; _player = null;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _player;
    final duration = _number(_media?['duration']);
    final pos = _number(_media?['position']).clamp(0.0, duration).toDouble();
    return Scaffold(
      appBar: AppBar(title: const Text('Z Music · Live'), actions: [
        IconButton(tooltip: 'Refresh permissions and library', onPressed: _busy || _opening ? null : () => _load(reset: true), icon: const Icon(Icons.refresh)),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<bool>(segments: const [
          ButtonSegment(value: false, label: Text('Phone'), icon: Icon(Icons.phone_android)),
          ButtonSegment(value: true, label: Text('PC'), icon: Icon(Icons.computer)),
        ], selected: {_pc}, onSelectionChanged: _opening || _busy ? null : (values) async {
          await _stopPhone(); if (mounted) setState(() { _pc = values.first; _seek = null; });
        }),
        const SizedBox(height: 12),
        Text(_pc ? (_control ? 'PC controls enabled' : 'PC control not granted') :
          (_stream ? 'Phone streaming enabled' : 'Streaming not granted')),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (!_stream && !_control) const Text('Open Media Player 1.5.1 on PC and enable the Live Server music switches and this device’s permissions.'),
        if (_pc) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          Text('${_media?['title'] ?? 'PC status not shared'}', style: Theme.of(context).textTheme.titleLarge),
          if (duration > 0) Slider(value: (_seek ?? pos).clamp(0.0,duration).toDouble(), max: duration,
            onChanged: !_control || _opening ? null : (v) => setState(() => _seek = v),
            onChangeEnd: !_control || _opening ? null : (v) {setState(() => _seek = null); unawaited(_command('seek', value: v));}),
          Text('${_clock(pos)} / ${_clock(duration)}'),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(tooltip: 'Previous', onPressed: _control && !_opening ? () => _command('previous') : null, icon: const Icon(Icons.skip_previous)),
            IconButton(tooltip: 'Play', onPressed: _control && !_opening ? () => _command('play') : null, icon: const Icon(Icons.play_arrow)),
            IconButton(tooltip: 'Pause', onPressed: _control && !_opening ? () => _command('pause') : null, icon: const Icon(Icons.pause)),
            IconButton(tooltip: 'Next', onPressed: _control && !_opening ? () => _command('next') : null, icon: const Icon(Icons.skip_next)),
          ]),
        ]))),
        if (!_pc && p != null && _current != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          Text('${_current!['title']}', style: Theme.of(context).textTheme.titleLarge),
          Text('${_current!['artist'] ?? ''}'),
          StreamBuilder<Duration>(stream: p.positionStream, builder: (context,snapshot) {
            final max = (p.duration?.inMilliseconds ?? 0).toDouble();
            final position = (snapshot.data?.inMilliseconds ?? 0).toDouble();
            return Column(children: [
              if (max > 0) Slider(value: position.clamp(0.0,max).toDouble(), max: max,
                onChanged: !_stream || _opening ? null : (v) => unawaited(p.seek(Duration(milliseconds: v.round())).catchError((Object _) {}))),
              Text('${_clock(position/1000)} / ${_clock(max/1000)}'),
            ]);
          }),
          StreamBuilder<bool>(stream: p.playingStream, builder: (context,snapshot) => IconButton(
            tooltip: snapshot.data == true ? 'Pause' : 'Play',
            onPressed: !_stream || _opening ? null : () {
              if (p.playing) { unawaited(p.pause()); } else { unawaited(p.play().catchError((Object _) {})); }
            }, icon: Icon(snapshot.data == true ? Icons.pause_circle : Icons.play_circle), iconSize: 48)),
        ]))),
        const SizedBox(height: 12),
        if (_stream) ...[
          TextField(controller: _search, maxLength: 200, textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(reset: true),
            decoration: InputDecoration(labelText: 'Search PC library', suffixIcon: IconButton(
              onPressed: _busy || _opening ? null : () => _load(reset: true), icon: const Icon(Icons.search)))),
          for (final song in _songs) Card(child: ListTile(
            leading: const Icon(Icons.music_note), title: Text('${song['title'] ?? 'Track'}'),
            subtitle: Text('${song['artist'] ?? ''} · ${song['album'] ?? ''}'),
            trailing: Text(_clock(_number(song['duration']))),
            enabled: !_opening && !_busy && (!_pc || _control), onTap: () => _playTrack(song))),
          if (_more) OutlinedButton(onPressed: _busy || _opening ? null : () => _load(reset: false), child: const Text('Load more')),
          if (!_busy && _songs.isEmpty) const Text('No tracks found.'),
        ],
        if (_busy || _opening) const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 8),
        const Text('Phone playback stops when leaving this screen or backgrounding the app. Use only your private Tailscale network.'),
      ]),
    );
  }
}
