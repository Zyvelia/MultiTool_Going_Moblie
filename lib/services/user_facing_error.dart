import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// One English sentence (plus a next step) for anything the phone surfaces.
String explainError(Object error, {String? doing}) {
  if (error is AppIssue) {
    return error.message;
  }
  if (error is TimeoutException) {
    return _withDoing(
      'The PC did not answer in time. Is Tailscale on, and is Remote Hub on Go Live?',
      doing,
    );
  }
  if (error is HandshakeException || error is TlsException || error is CertificateException) {
    return _withDoing(
      'The secure connection to the PC failed. Confirm Tailscale is up and the hostname in Settings matches the PC.',
      doing,
    );
  }
  if (error is SocketException) {
    return _withDoing(_fromSocket(error), doing);
  }
  if (error is HttpException) {
    return _withDoing(_fromText(error.message), doing);
  }
  if (error is FormatException) {
    return _withDoing(
      'The PC sent something this app could not read. Go Live again on Remote Hub, then retry.',
      doing,
    );
  }
  if (error is ArgumentError) {
    final raw = error.message?.toString() ?? error.toString();
    if (raw.contains('unknown module')) {
      return 'This screen is not wired to a PC port yet. Set the Tailscale hostname in Settings, or that feature is not on this build.';
    }
    return _withDoing('Something in the app was set up wrong. Check Settings.', doing);
  }

  return _withDoing(_fromText(error.toString()), doing);
}

/// Turn an HTTP reply into a thrown [AppIssue] the UI can show as-is.
Never throwHttp(http.Response res, {required String doing}) {
  throw AppIssue.fromHttp(res.statusCode, res.body, doing: doing);
}

void ensureOk(http.Response res, {required String doing, bool requireOk = false}) {
  final data = tryJsonMap(res.body);
  final statusOk = res.statusCode >= 200 && res.statusCode < 300;
  if (statusOk && !requireOk) return;
  if (statusOk && requireOk && data != null && data['ok'] == true) return;
  if (statusOk && requireOk && data != null && data['ok'] == null) return;
  throw AppIssue.fromHttp(res.statusCode, res.body, doing: doing);
}

Map<String, dynamic>? tryJsonMap(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return null;
}

class AppIssue implements Exception {
  final String message;
  const AppIssue(this.message);

  factory AppIssue.fromHttp(int status, String body, {required String doing}) {
    final data = tryJsonMap(body);
    final server = (data?['error'] ?? data?['message'] ?? '').toString().trim();
    final code = (data?['code'] ?? '').toString().trim();
    final core = _fromServer(server, code) ?? _fromHttpStatus(status, server);
    return AppIssue(_withDoing(core, doing));
  }

  @override
  String toString() => message;
}

String _withDoing(String core, String? doing) {
  if (doing == null || doing.isEmpty) return core;
  final lead = doing.trim();
  final lower = lead.toLowerCase();
  final prefix = lower.startsWith("couldn't") || lower.startsWith('could not')
      ? '${lead[0].toUpperCase()}${lead.substring(1)}'
      : "Couldn't $lead";
  if (core.toLowerCase().startsWith(prefix.toLowerCase())) return core;
  return '$prefix. $core';
}

String? _fromServer(String server, String code) {
  if (code == 'device_untrusted' || server.contains('device_untrusted')) {
    return 'This phone is not paired, or it was revoked on the PC. Pair it in Settings. If the phone is stolen, tap Revoke on Remote Hub.';
  }
  if (server.isEmpty) return null;
  final lower = server.toLowerCase();
  if (lower.contains('pair') && (lower.contains('revok') || lower.contains('only answers'))) {
    return server;
  }
  if (lower.contains('wrong or missing access code') || lower.contains('wrong access code')) {
    return 'The access code does not match. Open Settings on this phone and type the same code as the PC module.';
  }
  if (lower.contains('not authenticated') ||
      lower.contains('incorrect master password') ||
      lower.contains('master password')) {
    return 'Wrong vault password, or the vault locked itself. Type the master password again.';
  }
  if (lower.contains('invite') && lower.contains('key')) {
    return 'That Night invite key was rejected. Copy a fresh key from Tailnet Social on the PC.';
  }
  if (lower.contains('pairing code expired')) {
    return 'That pairing code expired. Issue a new one on Remote Hub (valid about 10 minutes).';
  }
  if (lower.contains('wrong pairing code')) {
    return 'That pairing code is wrong. Use the 6 digits showing on Remote Hub right now.';
  }
  if (lower.contains('clock is too far')) {
    return 'This phone’s clock is too far off the PC. Turn on automatic date & time, then retry.';
  }
  // Desktop already wrote English — keep it, strip jargon wrappers.
  if (server.length < 220 && !server.contains('Exception') && !RegExp(r'\berrno\b').hasMatch(lower)) {
    return server;
  }
  return null;
}

String _fromHttpStatus(int? status, String extra) {
  final known = _fromServer(extra, '');
  if (known != null) return known;
  switch (status) {
    case 401:
      return 'This PC asked for an access code. Put the same code in Settings as on the desktop module.';
    case 403:
      return 'This PC refused the request. Pair this phone in Settings, or the access code is wrong.';
    case 404:
      return 'Nothing on the PC answered that request. Go Live on Remote Hub, then retry.';
    case 408:
    case 504:
      return 'The PC or Tailscale timed out. Try again in a moment.';
    case 409:
      return 'The PC is busy with something else. Wait a few seconds and retry.';
    case 413:
      return 'That file is too large for this transfer.';
    case 429:
      return 'Too many tries. Wait a minute, then retry.';
    case 500:
    case 501:
      return 'The PC hit an internal error. Check that module on the desktop, then retry.';
    case 502:
    case 503:
      return 'Tailscale dropped the hop to the PC. Keep Tailscale on and tap Go Live, then retry.';
    default:
      if (status != null && status >= 400) {
        return 'The PC answered with an error ($status). Go Live on Remote Hub and retry.';
      }
      return extra.isNotEmpty
          ? extra
          : 'The PC did not complete that request. Go Live on Remote Hub and retry.';
  }
}

String _fromSocket(SocketException e) {
  final msg = '${e.message} ${e.osError ?? ''}'.toLowerCase();
  return _networkBlurb(msg);
}

String _fromText(String raw) {
  var text = raw.trim();
  text = text.replaceFirst(
    RegExp(
      r'^(Exception|AppIssue|ControlException|ClientException|HttpException|SocketException|HandshakeException|TimeoutException|FormatException|TlsException|CertificateException|StateError|OsError):\s*',
      caseSensitive: false,
    ),
    '',
  );
  text = text.replaceFirst(RegExp(r',\s*uri=.*$'), '');

  final json = tryJsonMap(text);
  if (json != null) {
    final server = (json['error'] ?? json['message'] ?? '').toString();
    final code = (json['code'] ?? '').toString();
    final from = _fromServer(server, code);
    if (from != null) return from;
  }

  final statusMatch = RegExp(r'\b(status\s*)?(\d{3})\b').firstMatch(text);
  if (statusMatch != null) {
    final status = int.tryParse(statusMatch.group(2)!);
    if (status != null && status >= 400) {
      return _fromHttpStatus(status, text);
    }
  }

  final lower = text.toLowerCase();
  if (lower.contains('device_untrusted') ||
      lower.contains('only answers paired') ||
      lower.contains('was revoked')) {
    return 'This phone is not paired, or it was revoked on the PC. Pair it in Settings. If the phone is stolen, tap Revoke on Remote Hub.';
  }

  final net = _networkBlurb(lower);
  if (net != text && _looksNetwork(lower)) return net;

  if (lower.contains('certificate') || lower.contains('handshake') || lower.contains('ssl') || lower.contains('tls')) {
    return 'The secure connection to the PC failed. Confirm Tailscale is up and the hostname in Settings matches the PC.';
  }
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return 'The PC did not answer in time. Is Tailscale on, and is Remote Hub on Go Live?';
  }
  if (lower.contains('not connected') || lower.contains('websocket')) {
    return 'The live link to the PC dropped. Keep Tailscale on and wait a second — it will reconnect.';
  }
  if (lower.contains('source error') || lower.contains('failed to load url') || lower.contains('playback')) {
    return 'Playback failed. The stream from the PC dropped. Try the song again; if it keeps failing, Go Live on Remote Hub.';
  }
  if (lower.contains('permission') && (lower.contains('photo') || lower.contains('storage') || lower.contains('denied'))) {
    return 'This phone blocked Photos or Files access. Allow it in system Settings, then retry.';
  }
  if (lower.contains('no space') || lower.contains('enospc')) {
    return 'This phone is out of storage. Free some space, then retry.';
  }

  if (text.length > 180 || _looksNetwork(lower) || lower.contains('errno')) {
    return _networkBlurb(lower);
  }
  if (text.isEmpty) {
    return 'Something failed and the app did not get a reason. Retry, or Go Live on Remote Hub.';
  }
  return text;
}

bool _looksNetwork(String lower) {
  return lower.contains('socket') ||
      lower.contains('connection') ||
      lower.contains('host lookup') ||
      lower.contains('errno') ||
      lower.contains('network') ||
      lower.contains('unreachable') ||
      lower.contains('refused') ||
      lower.contains('reset') ||
      lower.contains('broken pipe') ||
      lower.contains('failed host');
}

String _networkBlurb(String lower) {
  if (lower.contains('failed host lookup') || lower.contains('name or service not known') || lower.contains('no address associated')) {
    return 'Cannot find that PC name on the network. Check Tailscale is signed in on both devices, and the hostname in Settings matches the PC.';
  }
  if (lower.contains('connection refused') || lower.contains('errno = 111') || lower.contains('errno = 61')) {
    return 'The PC is not accepting this connection. Open Remote Hub and tap Go Live.';
  }
  if (lower.contains('network is unreachable') || lower.contains('no route') || lower.contains('errno = 101') || lower.contains('errno = 51')) {
    return 'This phone has no route to the PC. Turn Tailscale on (same tailnet), then retry.';
  }
  if (lower.contains('connection reset') || lower.contains('connection abort') || lower.contains('broken pipe') || lower.contains('connection closed')) {
    return 'The link to the PC dropped mid-request. Tailscale hiccup — try again.';
  }
  if (lower.contains('timed out') || lower.contains('timeout') || lower.contains('errno = 110') || lower.contains('errno = 60')) {
    return 'The PC did not answer in time. Is Tailscale on, and is Remote Hub on Go Live?';
  }
  if (lower.contains('connection failed') || lower.contains('clientexception')) {
    return 'Could not reach the PC. Turn Tailscale on, confirm the hostname in Settings, then Go Live on Remote Hub.';
  }
  return 'Could not reach the PC. Turn Tailscale on, confirm the hostname in Settings, then Go Live on Remote Hub.';
}
