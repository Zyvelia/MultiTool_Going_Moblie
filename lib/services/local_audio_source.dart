import 'dart:io';

import 'package:just_audio/just_audio.dart';

/// Plays a file already on the phone by serving it to ExoPlayer over
/// 127.0.0.1 with a real content type.
///
/// On Android 11, handing ExoPlayer a file:// path inside app storage
/// fails even when the same bytes play in Chrome. The website works
/// because the browser is given a URL and a content type.
class LocalFileAudioSource extends StreamAudioSource {
  LocalFileAudioSource(this.file, this.contentType, {super.tag});

  final File file;
  final String contentType;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final length = await file.length();
    final from = (start ?? 0).clamp(0, length);
    final to = (end ?? length).clamp(from, length);
    return StreamAudioResponse(
      rangeRequestsSupported: true,
      sourceLength: length,
      contentLength: to - from,
      offset: from,
      contentType: contentType,
      stream: file.openRead(from, to),
    );
  }
}

String mimeForAudioExt(String ext) {
  switch (ext.toLowerCase()) {
    case 'mp3':
      return 'audio/mpeg';
    case 'm4a':
    case 'm4b':
    case 'm4r':
    case 'mp4':
      return 'audio/mp4';
    case 'aac':
      return 'audio/aac';
    case 'wav':
    case 'wave':
      return 'audio/wav';
    case 'flac':
      return 'audio/flac';
    case 'ogg':
    case 'opus':
      return 'audio/ogg';
    case 'webm':
      return 'audio/webm';
    case 'aiff':
    case 'aif':
      return 'audio/aiff';
    default:
      return 'application/octet-stream';
  }
}
