import 'dart:io';
import 'dart:typed_data';

/// Wake-on-LAN over the local network (UDP magic packet). Does not use Tailscale.
class WolException implements Exception {
  WolException(this.message);
  final String message;
  @override
  String toString() => message;
}

class WolSendResult {
  const WolSendResult({
    required this.bytesSent,
    required this.destination,
    required this.port,
  });

  final int bytesSent;
  final String destination;
  final int port;
}

class WolService {
  static const int magicPacketLength = 6 + 16 * 6;

  /// Accepts `aa:bb:cc:dd:ee:ff` or `aa-bb-cc-dd-ee-ff` (case insensitive).
  static List<int> parseMacAddress(String mac) {
    final trimmed = mac.trim();
    if (!RegExp(r'^([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}$').hasMatch(trimmed)) {
      throw WolException(
        'MAC must look like aa:bb:cc:dd:ee:ff or aa-bb-cc-dd-ee-ff.',
      );
    }
    final hex = trimmed.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (hex.length != 12) {
      throw WolException('MAC must be 12 hex digits.');
    }
    final out = <int>[];
    for (var i = 0; i < 12; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  static Uint8List buildMagicPacket(List<int> macBytes) {
    if (macBytes.length != 6) {
      throw WolException('MAC must be exactly 6 bytes.');
    }
    final packet = Uint8List(magicPacketLength);
    for (var i = 0; i < 6; i++) {
      packet[i] = 0xFF;
    }
    for (var rep = 0; rep < 16; rep++) {
      final offset = 6 + rep * 6;
      for (var b = 0; b < 6; b++) {
        packet[offset + b] = macBytes[b];
      }
    }
    return packet;
  }

  static int parsePort(String text, {int defaultPort = 9}) {
    final v = text.trim();
    if (v.isEmpty) return defaultPort;
    final port = int.tryParse(v);
    if (port == null || port < 1 || port > 65535) {
      throw WolException('UDP port must be between 1 and 65535.');
    }
    return port;
  }

  static InternetAddress parseBroadcast(String broadcast) {
    final v = broadcast.trim();
    if (v.isEmpty) {
      throw WolException('Enter a broadcast address (e.g. 192.168.1.255).');
    }
    try {
      final addr = InternetAddress(v);
      if (addr.type != InternetAddressType.IPv4) {
        throw WolException('Broadcast must be an IPv4 address.');
      }
      return addr;
    } catch (_) {
      throw WolException('Invalid broadcast address: $v');
    }
  }

  /// Builds the packet and checks config without sending (safe diagnostic).
  static WolSendResult validateConfiguration({
    required String macAddress,
    required String broadcast,
    required int port,
  }) {
    final mac = parseMacAddress(macAddress);
    final packet = buildMagicPacket(mac);
    parseBroadcast(broadcast);
    if (port < 1 || port > 65535) {
      throw WolException('UDP port must be between 1 and 65535.');
    }
    return WolSendResult(
      bytesSent: packet.length,
      destination: broadcast.trim(),
      port: port,
    );
  }

  /// Sends a magic packet on the local LAN. Requires Wi‑Fi and correct subnet broadcast on iOS.
  static Future<WolSendResult> send({
    required String macAddress,
    String broadcast = '255.255.255.255',
    int port = 9,
  }) async {
    validateConfiguration(
      macAddress: macAddress,
      broadcast: broadcast,
      port: port,
    );
    final mac = parseMacAddress(macAddress);
    final packet = buildMagicPacket(mac);
    final dest = parseBroadcast(broadcast);

    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      final sent = socket.send(packet, dest, port);
      if (sent != packet.length) {
        throw WolException(
          'Only $sent of ${packet.length} bytes were sent. Check Wi‑Fi and try your subnet broadcast (e.g. 192.168.x.255), not only 255.255.255.255.',
        );
      }
      return WolSendResult(
        bytesSent: sent,
        destination: dest.address,
        port: port,
      );
    } on SocketException catch (e) {
      throw WolException(
        'Could not send wake packet (${e.message}). '
        'Connect to home Wi‑Fi and verify the broadcast address.',
      );
    } on IOException catch (e) {
      throw WolException('Network error: $e');
    } finally {
      socket?.close();
    }
  }
}
