import 'dart:convert';

import 'trusted_http.dart';
import 'user_facing_error.dart';
import 'wol_service.dart';

/// Asks an always-on home machine (laptop relay) to send a LAN magic packet.
class WolRelayService {
  final String baseUrl;
  final String? accessCode;

  WolRelayService(this.baseUrl, {this.accessCode});

  Future<WolSendResult> wake({
    required String macAddress,
    required String broadcast,
    required int port,
  }) async {
    WolService.validateConfiguration(
      macAddress: macAddress,
      broadcast: broadcast,
      port: port,
    );
    final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/wake');
    final res = await trustedHttp.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (accessCode != null && accessCode!.isNotEmpty) 'X-Access-Code': accessCode!,
      },
      body: jsonEncode({
        'mac_address': macAddress.trim(),
        'broadcast': broadcast.trim().isEmpty ? '255.255.255.255' : broadcast.trim(),
        'port': port,
      }),
    );
    ensureOk(res, doing: 'wake the PC through your home relay');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['ok'] != true) {
      throw AppIssue((data['error'] as String?) ?? 'Relay refused the wake request');
    }
    return WolSendResult(
      bytesSent: (data['bytes_sent'] as num?)?.toInt() ?? WolService.magicPacketLength,
      destination: (data['destination'] as String?) ?? broadcast,
      port: (data['port'] as num?)?.toInt() ?? port,
    );
  }
}
