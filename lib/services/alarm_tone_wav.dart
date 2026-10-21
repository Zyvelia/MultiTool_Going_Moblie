import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Writes short looping-friendly WAV clips for built-in alarm tones.
class AlarmToneWav {
  static const sampleRate = 22050;

  static Future<File> fileForBuiltin(String builtinId) async {
    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory('${dir.path}/alarm_tones');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    final out = File('${outDir.path}/$builtinId.wav');
    if (out.existsSync()) return out;
    final bytes = _waveform(builtinId);
    await out.writeAsBytes(bytes, flush: true);
    return out;
  }

  static Uint8List _waveform(String id) {
    switch (id) {
      case 'klaxon':
        return _build(_klaxon);
      case 'siren':
        return _build(_siren);
      case 'brain_melt':
        return _build(_brainMelt);
      case 'foghorn':
        return _build(_foghorn);
      case 'chaos':
        return _build(_chaos);
      default:
        return _build(_klaxon);
    }
  }

  static double _klaxon(double t) {
    final phase = (t * 6).floor() % 2 == 0 ? 880.0 : 440.0;
    return sin(2 * pi * phase * t) * 0.85;
  }

  static double _siren(double t) {
    final sweep = 400 + 800 * (0.5 + 0.5 * sin(2 * pi * 1.2 * t));
    return sin(2 * pi * sweep * t) * 0.9;
  }

  static double _brainMelt(double t) {
    final burst = sin(2 * pi * 1400 * t);
    final gate = sin(2 * pi * 8 * t) > 0.2 ? 1.0 : 0.0;
    return burst * gate * 0.95;
  }

  static double _foghorn(double t) {
    final low = sin(2 * pi * 110 * t);
    final pulse = 0.5 + 0.5 * sin(2 * pi * 0.7 * t);
    return low * pulse * 0.95;
  }

  static double _chaos(double t) {
    final idx = (t * 12).floor();
    final freqs = [320.0, 523.0, 784.0, 1046.0, 660.0, 990.0];
    final f = freqs[idx % freqs.length];
    return sin(2 * pi * f * t) * 0.9;
  }

  static Uint8List _build(double Function(double t) fn, {double durationSec = 2.0}) {
    final n = (sampleRate * durationSec).round();
    final pcm = Int16List(n);
    for (var i = 0; i < n; i++) {
      final t = i / sampleRate;
      final sample = fn(t).clamp(-1.0, 1.0);
      pcm[i] = (sample * 32767).round();
    }
    return _wrapWav(pcm);
  }

  static Uint8List _wrapWav(Int16List pcm) {
    final dataSize = pcm.lengthInBytes;
    final fileSize = 36 + dataSize;
    final b = BytesBuilder();
    b.add('RIFF'.codeUnits);
    b.add(_le32(fileSize));
    b.add('WAVE'.codeUnits);
    b.add('fmt '.codeUnits);
    b.add(_le32(16));
    b.add(_le16(1)); // PCM
    b.add(_le16(1)); // mono
    b.add(_le32(sampleRate));
    b.add(_le32(sampleRate * 2));
    b.add(_le16(2));
    b.add(_le16(16));
    b.add('data'.codeUnits);
    b.add(_le32(dataSize));
    b.add(pcm.buffer.asUint8List());
    return b.toBytes();
  }

  static List<int> _le16(int v) => [v & 0xff, (v >> 8) & 0xff];
  static List<int> _le32(int v) => [
        v & 0xff,
        (v >> 8) & 0xff,
        (v >> 16) & 0xff,
        (v >> 24) & 0xff,
      ];
}
