import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Which stage of the test is currently running (or just finished).
enum SpeedTestPhase { idle, ping, download, upload, done, error }

/// Snapshot of everything measured so far. Fields are filled in as each
/// phase completes, so the UI can render partial results while later
/// phases are still running instead of waiting for the whole run.
class SpeedTestResult {
  final double? pingMs;
  final double? jitterMs;
  final double? pingMinMs;
  final double? pingMaxMs;
  final double? serverPingMs;
  final double? downloadMbps;
  final double? uploadMbps;
  final String? error;

  const SpeedTestResult({
    this.pingMs,
    this.jitterMs,
    this.pingMinMs,
    this.pingMaxMs,
    this.serverPingMs,
    this.downloadMbps,
    this.uploadMbps,
    this.error,
  });

  SpeedTestResult copyWith({
    double? pingMs,
    double? jitterMs,
    double? pingMinMs,
    double? pingMaxMs,
    double? serverPingMs,
    double? downloadMbps,
    double? uploadMbps,
    String? error,
  }) {
    return SpeedTestResult(
      pingMs: pingMs ?? this.pingMs,
      jitterMs: jitterMs ?? this.jitterMs,
      pingMinMs: pingMinMs ?? this.pingMinMs,
      pingMaxMs: pingMaxMs ?? this.pingMaxMs,
      serverPingMs: serverPingMs ?? this.serverPingMs,
      downloadMbps: downloadMbps ?? this.downloadMbps,
      uploadMbps: uploadMbps ?? this.uploadMbps,
      error: error ?? this.error,
    );
  }
}

/// Emitted throughout a run — [phase] says what's active right now,
/// [liveMbps] is a rolling in-progress reading during download/upload
/// (null otherwise), and [result] carries every value finalized so far.
class SpeedTestProgress {
  final SpeedTestPhase phase;
  final double? liveMbps;
  final SpeedTestResult result;

  const SpeedTestProgress(this.phase, this.result, {this.liveMbps});
}

/// Runs a Wi-Fi/cellular speed test: latency (with jitter), download
/// throughput, and upload throughput, against Cloudflare's public speed
/// test endpoints (the same ones speed.cloudflare.com itself uses —
/// no API key, no size limits, and not affiliated with any one ISP so
/// results aren't skewed by a provider testing against its own CDN).
///
/// If [serverBaseUrl] is supplied to [run], a single extra request also
/// times a round trip to that host's `/api/status` — handy for telling
/// "my internet is fine but the Tailscale hop to my PC is slow" apart
/// from a general connectivity problem.
class SpeedTestService {
  static const int _downloadBytes = 25 * 1000 * 1000; // 25 MB
  static const int _uploadBytes = 8 * 1000 * 1000; // 8 MB
  static const int _uploadChunkSize = 64 * 1024;
  static const Duration _downloadCap = Duration(seconds: 15);
  static const Duration _uploadCap = Duration(seconds: 15);

  final http.Client _client = http.Client();

  /// Starts a full run and streams progress until [SpeedTestPhase.done]
  /// or [SpeedTestPhase.error]. The returned stream closes itself after
  /// the terminal event — callers don't need to cancel it manually.
  Stream<SpeedTestProgress> run({String? serverBaseUrl}) {
    final controller = StreamController<SpeedTestProgress>();
    unawaited(_runInternal(controller, serverBaseUrl));
    return controller.stream;
  }

  Future<void> _runInternal(
    StreamController<SpeedTestProgress> controller,
    String? serverBaseUrl,
  ) async {
    var result = const SpeedTestResult();
    try {
      controller.add(SpeedTestProgress(SpeedTestPhase.ping, result));
      final ping = await _measurePing();
      double? serverPing;
      if (serverBaseUrl != null && serverBaseUrl.isNotEmpty) {
        serverPing = await _measureServerPing(serverBaseUrl);
      }
      result = result.copyWith(
        pingMs: ping.avg,
        jitterMs: ping.jitter,
        pingMinMs: ping.min,
        pingMaxMs: ping.max,
        serverPingMs: serverPing,
      );
      controller.add(SpeedTestProgress(SpeedTestPhase.ping, result));

      controller.add(SpeedTestProgress(SpeedTestPhase.download, result));
      final download = await _measureDownload((mbps) {
        controller.add(
          SpeedTestProgress(SpeedTestPhase.download, result, liveMbps: mbps),
        );
      });
      result = result.copyWith(downloadMbps: download);
      controller.add(SpeedTestProgress(SpeedTestPhase.download, result));

      controller.add(SpeedTestProgress(SpeedTestPhase.upload, result));
      final upload = await _measureUpload((mbps) {
        controller.add(
          SpeedTestProgress(SpeedTestPhase.upload, result, liveMbps: mbps),
        );
      });
      result = result.copyWith(uploadMbps: upload);

      controller.add(SpeedTestProgress(SpeedTestPhase.done, result));
    } catch (e) {
      controller.add(
        SpeedTestProgress(SpeedTestPhase.error, result.copyWith(error: '$e')),
      );
    } finally {
      await controller.close();
    }
  }

  /// Six small round trips to Cloudflare's zero-byte endpoint. The first
  /// is discarded — it pays for DNS + TLS handshake and would otherwise
  /// make latency look far worse than the "warm connection" number a
  /// person actually cares about. Jitter is the average change between
  /// consecutive samples, matching how most speed test tools report it.
  Future<({double avg, double jitter, double min, double max})>
      _measurePing() async {
    final samples = <double>[];
    for (var i = 0; i < 6; i++) {
      final sw = Stopwatch()..start();
      try {
        final res = await _client
            .get(Uri.parse(
                'https://speed.cloudflare.com/__down?bytes=0&cb=${_cacheBust()}'))
            .timeout(const Duration(seconds: 5));
        sw.stop();
        if (res.statusCode == 200 && i > 0) {
          samples.add(sw.elapsedMicroseconds / 1000);
        }
      } catch (_) {
        // One dropped probe shouldn't fail the whole test; only an
        // empty sample set below does that.
      }
    }
    if (samples.isEmpty) {
      throw Exception('No response from test server — check your connection');
    }
    final avg = samples.reduce((a, b) => a + b) / samples.length;
    double jitterSum = 0;
    for (var i = 1; i < samples.length; i++) {
      jitterSum += (samples[i] - samples[i - 1]).abs();
    }
    final jitter = samples.length > 1 ? jitterSum / (samples.length - 1) : 0.0;
    return (
      avg: avg,
      jitter: jitter,
      min: samples.reduce(min),
      max: samples.reduce(max),
    );
  }

  /// Single timed GET to the user's own configured server, mirroring
  /// the check ConnectionTestService does — kept best-effort (returns
  /// null rather than throwing) so a slow/offline home server doesn't
  /// take down the rest of the speed test.
  Future<double?> _measureServerPing(String baseUrl) async {
    final sw = Stopwatch()..start();
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/api/status'))
          .timeout(const Duration(seconds: 6));
      sw.stop();
      return res.statusCode == 200 ? sw.elapsedMicroseconds / 1000 : null;
    } catch (_) {
      return null;
    }
  }

  /// Streams up to 25 MB down from Cloudflare, reporting a rolling
  /// Mbps figure roughly every 150ms via [onProgress]. Capped at 15s
  /// wall clock (using whatever arrived by then) so a very slow link
  /// doesn't leave the test running indefinitely instead of just
  /// reporting the low number.
  Future<double> _measureDownload(void Function(double mbps) onProgress) async {
    final uri = Uri.parse(
        'https://speed.cloudflare.com/__down?bytes=$_downloadBytes&cb=${_cacheBust()}');
    final response = await _client
        .send(http.Request('GET', uri))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Download test failed: HTTP ${response.statusCode}');
    }

    final sw = Stopwatch()..start();
    int received = 0;
    int lastReportMs = 0;
    final completer = Completer<void>();
    late StreamSubscription<List<int>> sub;

    sub = response.stream.listen(
      (chunk) {
        received += chunk.length;
        final elapsedMs = sw.elapsedMilliseconds;
        if (elapsedMs - lastReportMs > 150 && elapsedMs > 0) {
          onProgress((received * 8) / (elapsedMs / 1000) / 1e6);
          lastReportMs = elapsedMs;
        }
        if (sw.elapsed > _downloadCap) {
          sub.cancel();
          if (!completer.isCompleted) completer.complete();
        }
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      cancelOnError: true,
    );

    await completer.future;
    sw.stop();

    final elapsedSec = sw.elapsedMilliseconds / 1000;
    if (elapsedSec <= 0 || received == 0) {
      throw Exception('No data received during download test');
    }
    return (received * 8) / elapsedSec / 1e6;
  }

  /// Uploads up to 8 MB to Cloudflare in 64KB chunks, reporting a
  /// rolling Mbps figure as chunks are handed off. Real backpressure
  /// comes from [http.StreamedRequest]'s sink — Dart pauses the source
  /// while the underlying socket buffer is full, so throughput here
  /// tracks the actual wire speed rather than just "how fast this
  /// device can generate bytes". Capped at 15s the same way download is.
  Future<double> _measureUpload(void Function(double mbps) onProgress) async {
    final chunk = _randomChunk(_uploadChunkSize);
    final uri = Uri.parse('https://speed.cloudflare.com/__up');
    final request = http.StreamedRequest('POST', uri);
    request.headers['Content-Type'] = 'application/octet-stream';

    final sw = Stopwatch()..start();
    int sent = 0;
    int lastReportMs = 0;
    var capped = false;

    final feed = () async {
      while (sent < _uploadBytes && !capped) {
        final remaining = _uploadBytes - sent;
        final piece =
            remaining < chunk.length ? chunk.sublist(0, remaining) : chunk;
        request.sink.add(piece);
        sent += piece.length;

        final elapsedMs = sw.elapsedMilliseconds;
        if (elapsedMs - lastReportMs > 150 && elapsedMs > 0) {
          onProgress((sent * 8) / (elapsedMs / 1000) / 1e6);
          lastReportMs = elapsedMs;
        }
        if (sw.elapsed > _uploadCap) {
          capped = true;
        }
        // Yield so the event loop can actually drain the sink into the
        // socket between chunks instead of queuing everything at once.
        await Future<void>.delayed(Duration.zero);
      }
      await request.sink.close();
    }();

    final response = await _client.send(request).timeout(_uploadCap + const Duration(seconds: 5));
    await feed;
    await response.stream.drain<void>();
    sw.stop();

    final elapsedSec = sw.elapsedMilliseconds / 1000;
    if (elapsedSec <= 0 || sent == 0) {
      throw Exception('No data sent during upload test');
    }
    return (sent * 8) / elapsedSec / 1e6;
  }

  Uint8List _randomChunk(int size) {
    final rnd = Random();
    final bytes = Uint8List(size);
    for (var i = 0; i < size; i += 4) {
      final v = rnd.nextInt(1 << 32);
      bytes[i] = v & 0xFF;
      if (i + 1 < size) bytes[i + 1] = (v >> 8) & 0xFF;
      if (i + 2 < size) bytes[i + 2] = (v >> 16) & 0xFF;
      if (i + 3 < size) bytes[i + 3] = (v >> 24) & 0xFF;
    }
    return bytes;
  }

  String _cacheBust() => DateTime.now().microsecondsSinceEpoch.toString();

  void dispose() => _client.close();
}
