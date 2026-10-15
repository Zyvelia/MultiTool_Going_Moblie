import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/stream_api_service.dart';
import '../services/user_facing_error.dart';
import '../theme/app_colors.dart';

class RemoteDesktopScreen extends StatefulWidget {
  final StreamApiService api;
  final int fps;
  final bool inputEnabled;
  final bool useWebRtc;

  const RemoteDesktopScreen({
    super.key,
    required this.api,
    this.fps = 8,
    this.inputEnabled = true,
    this.useWebRtc = true,
  });

  @override
  State<RemoteDesktopScreen> createState() => _RemoteDesktopScreenState();
}

class _RemoteDesktopScreenState extends State<RemoteDesktopScreen> {
  Uint8List? _frame;
  String? _error;
  String? _modeLabel;
  bool _streaming = false;
  Timer? _timer;
  final GlobalKey _viewKey = GlobalKey();

  RTCPeerConnection? _pc;
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  bool _rendererReady = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _streaming = false;
    unawaited(_teardownWebRtc());
    super.dispose();
  }

  Future<void> _teardownWebRtc() async {
    await widget.api.stopWebrtc();
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    if (_rendererReady) {
      await _renderer.dispose();
      _rendererReady = false;
    }
  }

  Future<void> _start() async {
    if (widget.useWebRtc) {
      final ok = await _startWebRtc();
      if (ok) return;
    }
    _startJpegFallback();
  }

  Future<bool> _startWebRtc() async {
    setState(() {
      _error = null;
      _modeLabel = 'Connecting WebRTC…';
    });
    try {
      await _renderer.initialize();
      _rendererReady = true;

      final pc = await createPeerConnection({
        'sdpSemantics': 'unified-plan',
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      });
      _pc = pc;

      pc.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          _renderer.srcObject = event.streams.first;
          if (mounted) {
            setState(() {
              _modeLabel = 'WebRTC';
              _error = null;
            });
          }
        }
      };

      pc.onConnectionState = (state) {
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed && mounted) {
          setState(() => _error = 'WebRTC connection failed. Try again or use JPEG fallback.');
        }
      };

      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await _waitIceGathering(pc);

      final local = await pc.getLocalDescription();
      if (local == null || local.sdp == null) {
        throw AppIssue('Could not create a WebRTC offer on the phone');
      }

      final answer = await widget.api.webrtcOffer(sdp: local.sdp!, type: local.type ?? 'offer');
      await pc.setRemoteDescription(RTCSessionDescription(answer.sdp, answer.type));

      if (!mounted) return true;
      setState(() {
        _modeLabel = 'WebRTC';
        _streaming = true;
      });
      return true;
    } catch (e) {
      await _teardownWebRtc();
      if (!mounted) return false;
      setState(() {
        _error = '${explainError(e)} — falling back to JPEG.';
        _modeLabel = null;
      });
      return false;
    }
  }

  Future<void> _waitIceGathering(RTCPeerConnection pc) async {
    if (pc.iceGatheringState == RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }
    final done = Completer<void>();
    pc.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete && !done.isCompleted) {
        done.complete();
      }
    };
    await done.future.timeout(const Duration(seconds: 12));
  }

  void _startJpegFallback() {
    final interval = Duration(milliseconds: (1000 / widget.fps.clamp(1, 20)).round());
    _streaming = true;
    _timer = Timer.periodic(interval, (_) => _pullFrame());
    _pullFrame();
    if (mounted) {
      setState(() => _modeLabel = 'JPEG');
    }
  }

  Future<void> _pullFrame() async {
    if (!_streaming || _pc != null) return;
    try {
      final bytes = await widget.api.fetchScreenFrame();
      if (!mounted) return;
      setState(() {
        _frame = Uint8List.fromList(bytes);
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = explainError(e));
    }
  }

  Offset? _normFromLocal(Offset local, Size box) {
    if (box.width <= 0 || box.height <= 0) return null;
    return Offset(
      (local.dx / box.width).clamp(0.0, 1.0),
      (local.dy / box.height).clamp(0.0, 1.0),
    );
  }

  Future<void> _send(String type, Offset local, Size box) async {
    if (!widget.inputEnabled) return;
    final n = _normFromLocal(local, box);
    if (n == null) return;
    try {
      await widget.api.sendInput(type: type, x: n.dx, y: n.dy);
    } catch (_) {}
  }

  Widget _videoContent(Size box) {
    if (_rendererReady && _renderer.srcObject != null) {
      return InteractiveViewer(
        minScale: 1,
        maxScale: 3,
        child: RTCVideoView(
          _renderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
        ),
      );
    }
    if (_frame == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return InteractiveViewer(
      minScale: 1,
      maxScale: 3,
      child: Image.memory(
        _frame!,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        width: box.width,
        height: box.height,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_modeLabel == null ? 'Remote desktop' : 'Remote desktop · $_modeLabel'),
        backgroundColor: const Color(0xFF151922),
        actions: [
          if (_pc == null)
            IconButton(
              onPressed: _pullFrame,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh frame',
            ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_error!, style: const TextStyle(color: AppColors.accent)),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final box = Size(constraints.maxWidth, constraints.maxHeight);
                return Listener(
                  key: _viewKey,
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: widget.inputEnabled
                      ? (e) => _send('down', e.localPosition, box)
                      : null,
                  onPointerMove: widget.inputEnabled
                      ? (e) => _send('move', e.localPosition, box)
                      : null,
                  onPointerUp: widget.inputEnabled
                      ? (e) => _send('up', e.localPosition, box)
                      : null,
                  child: GestureDetector(
                    onDoubleTapDown: widget.inputEnabled
                        ? (d) async {
                            final x = (d.localPosition.dx / box.width).clamp(0.0, 1.0);
                            final y = (d.localPosition.dy / box.height).clamp(0.0, 1.0);
                            await widget.api.sendInput(type: 'down', x: x, y: y, button: 'right');
                            await widget.api.sendInput(type: 'up', x: x, y: y, button: 'right');
                          }
                        : null,
                    child: _videoContent(box),
                  ),
                );
              },
            ),
          ),
          if (!widget.inputEnabled)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'View-only — remote input is disabled on the PC.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Drag to move the pointer. Double-tap for right click. Pinch to zoom.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}
