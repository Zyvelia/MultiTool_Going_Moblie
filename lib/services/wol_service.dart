import 'dart:io';
import 'dart:typed_data';

/// Sends a Wake-on-LAN magic packet. Works when the phone is on the same LAN
/// as the sleeping PC (or your router forwards directed broadcasts).
class WolService {
  static List<int> _macBytes(String mac) {
    final hex = mac.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (hex.length != 12) {
      throw FormatException('MAC must be 12 hex digits');
    }
    final out = <int>[];
    for (var i = 0; i < 12; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  static Future<void> send({
    required String macAddress,
    String broadcast = '255.255.255.255',
    int port = 9,
  }) async {
    final mac = _macBytes(macAddress);
    final packet = BytesBuilder();
    packet.add(List.filled(6, 0xFF));
    for (var i = 0; i < 16; i++) {
      packet.add(mac);
    }
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
    );
    socket.broadcastEnabled = true;
    socket.send(packet.toBytes(), InternetAddress(broadcast), port);
    socket.close();
  }
}
